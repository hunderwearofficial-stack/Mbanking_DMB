import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../firebase_options.dart';
import '../../main.dart';
import '../../presentation/screens/notification/notification_screen.dart';
import '../constants/api_endpoints.dart';
import '../network/api_client.dart';
import '../security/secure_storage_service.dart';
import '../utils/app_logger.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

enum PushDestination { notifications }

class PushPayload {
  static PushDestination destination(Map<String, dynamic> data) => PushDestination.notifications;

  static String? ref(Map<String, dynamic> data) {
    final r = data['ref'];
    return r is String && RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(r) ? r : null;
  }

  static String encode(Map<String, dynamic> data) => jsonEncode(data);

  static Map<String, dynamic> decode(String? payload) {
    if (payload == null || payload.isEmpty) return const {};
    try {
      final v = jsonDecode(payload);
      return v is Map<String, dynamic> ? v : const {};
    } catch (_) {
      return const {};
    }
  }
}

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  static const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'dmb_notification_channel',
    'Notifikasi Bank DMB',
    description: 'Notifikasi transaksi, keamanan, dan informasi PT BPR Dana Mandiri Bogor',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );
  static const String _smallIcon = '@drawable/ic_stat_notification';

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  ApiClient? _api;
  bool _initialized = false;
  String? _registeredToken; // token already sent to the backend in this login session
  Map<String, dynamic>? _pendingOpen; // tapped before login
  final List<String> _shownIds = [];

  bool? permissionGranted;

  Future<void> initialize({ApiClient? apiClient}) async {
    _api = apiClient ?? _api;
    if (_initialized) return;
    if (Platform.isIOS) {
      _initialized = true;
      return;
    }
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      }
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings(_smallIcon),
          iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
        ),
        onDidReceiveNotificationResponse: (r) => _onOpened(PushPayload.decode(r.payload)),
      );
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      await _messaging.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _onOpened(m.data));
      _messaging.onTokenRefresh.listen((t) => _register(t));

      final initial = await _messaging.getInitialMessage().timeout(const Duration(seconds: 4), onTimeout: () => null);
      if (initial != null) _onOpened(initial.data);
      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _onOpened(PushPayload.decode(launch!.notificationResponse?.payload));
      }
      _initialized = true;
    } catch (e) {
      logDebug('FCM init gagal: $e');
    }
  }

  Future<bool> _isLoggedIn() async {
    try {
      return (await SecureStorageService().getAccessToken())?.isNotEmpty == true;
    } catch (_) {
      return false;
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    if (!Platform.isAndroid) return;
    final n = message.notification;
    if (n == null) return;
    final id = message.messageId ?? '${n.title}|${n.body}';
    if (_shownIds.contains(id)) return; // never show the same message twice
    _shownIds.add(id);
    if (_shownIds.length > 50) _shownIds.removeAt(0);
    _local.show(
      id.hashCode,
      n.title,
      n.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          icon: _smallIcon,
          largeIcon: const DrawableResourceAndroidBitmap('@drawable/ic_notification_logo'),
          color: const Color(0xFF033172),
          importance: Importance.max,
          priority: Priority.max,
          ticker: n.title,
        ),
      ),
      payload: PushPayload.encode(message.data),
    );
  }

  Future<void> _onOpened(Map<String, dynamic> data) async {
    final loggedIn = await _isLoggedIn();
    if (!loggedIn) {
      _pendingOpen = data; // details are shown only after the customer authenticates
      return;
    }
    _pendingOpen = null;
    final ref = PushPayload.ref(data);
    if (ref != null && _api != null) {
      try {
        await _api!.post(ApiEndpoints.notificationsOpened, data: {'ref': ref});
      } catch (_) {/* reporting is best effort */}
    }
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    switch (PushPayload.destination(data)) {
      case PushDestination.notifications:
        nav.push(MaterialPageRoute(builder: (_) => const NotificationScreen()));
    }
  }

  Future<bool> _ensurePermission() async {
    try {
      final settings = await _messaging.requestPermission(alert: true, badge: true, sound: true);
      var granted = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (Platform.isAndroid) {
        final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        granted = await android?.requestNotificationsPermission() ?? granted;
      }
      permissionGranted = granted;
      return granted;
    } catch (e) {
      logDebug('FCM izin notifikasi: $e');
      return false;
    }
  }

  Future<void> _register(String token) async {
    final api = _api;
    if (api == null || token.isEmpty || token == _registeredToken) return;
    final loggedIn = await _isLoggedIn();
    if (!loggedIn) return; // a token is linked to a customer only after authentication
    try {
      await api.post(ApiEndpoints.notificationsFcmToken,
          data: {'fcm_token': token, 'platform': Platform.isIOS ? 'ios' : 'android'});
      _registeredToken = token;
    } catch (e) {
      logDebug('FCM registrasi token gagal: $e'); // token value is never logged
    }
  }

  Future<void> syncStoredTokenIfLoggedIn({ApiClient? apiClient}) async {
    await initialize(apiClient: apiClient);
    if (!_initialized) return;
    await _ensurePermission();
    try {
      final token = await _messaging.getToken().timeout(const Duration(seconds: 10));
      if (token != null) await _register(token);
    } catch (e) {
      logDebug('FCM getToken gagal: $e');
    }
    final pending = _pendingOpen;
    if (pending != null) await _onOpened(pending);
  }

  void onLoggedOut() {
    _registeredToken = null;
    _pendingOpen = null;
  }
}
