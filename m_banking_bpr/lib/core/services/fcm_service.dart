import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../network/api_client.dart';
import '../utils/app_logger.dart';
import '../constants/api_endpoints.dart';
import '../security/secure_storage_service.dart';
import '../../firebase_options.dart';
import '../../main.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    logDebug('FCM Background message: ${message.messageId} - ${message.notification?.title}');
  } catch (e) {
    logDebug('FCM background error: $e');
  }
}

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'dmb_notification_channel',
    'Notifikasi Bank DMB',
    description: 'Kanal resmi notifikasi transaksi dan informasi PT BPR Dana Mandiri Bogor',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  bool _isInitialized = false;

  Future<void> _ensureFirebaseInitialized() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  }

  Future<void> initialize({ApiClient? apiClient}) async {
    if (_isInitialized) return;

    try {
      await _ensureFirebaseInitialized();
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Request permission on iOS / Android 13+
      try {
        final settings = await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        ).timeout(const Duration(seconds: 6));
        logDebug('FCM Permission status: ${settings.authorizationStatus}');

        await _messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (pe) {
        logDebug('FCM permission non-blocking error: $pe');
      }

      // Setup Local Notifications for Foreground display
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          logDebug('Local notification clicked: ${response.payload}');
        },
      );

      // Create Android Notification Channel & Request Android 13+ Notification Permission
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_channel);
      try {
        await androidPlugin?.requestNotificationsPermission();
      } catch (_) {}

      // Foreground message listener (handles both Notification & Data payload)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        logDebug('FCM Foreground message received: ${message.messageId} | ${message.notification?.title}');
        final title = message.notification?.title ?? message.data['title'] ?? 'M-Banking DMB';
        final body = message.notification?.body ?? message.data['body'] ?? message.data['message'] ?? 'Notifikasi transaksi baru diterima.';

        _localNotifications.show(
          message.hashCode,
          title,
          body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              icon: '@mipmap/ic_launcher',
              importance: Importance.max,
              priority: Priority.max,
              playSound: true,
              enableVibration: true,
              fullScreenIntent: true,
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          payload: message.data['route'] ?? message.data['category'] ?? '',
        );

        // 2. Also show executive floating in-app banner immediately
        final navCtx = appNavigatorKey.currentContext;
        if (navCtx != null) {
          ScaffoldMessenger.of(navCtx).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.white24,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.notifications_active, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          body,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF0B356D),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
              duration: const Duration(seconds: 6),
            ),
          );
        }
      });

      // App opened from background by clicking notification
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        logDebug('FCM opened app from notification: ${message.data}');
      });

      // Check initial message if app opened from terminated state
      final initialMessage = await _messaging.getInitialMessage().timeout(const Duration(seconds: 4)).catchError((_) => null);
      if (initialMessage != null) {
        logDebug('FCM launched app from terminated: ${initialMessage.data}');
      }

      // Get FCM Device Token with timeout
      try {
        final token = await _messaging.getToken().timeout(const Duration(seconds: 8));
        if (token != null && token.isNotEmpty) {
          // Token value is not logged (debugPrint also prints in release builds — audit DMB-034).
          await SecureStorageService().saveFCMToken(token);
          if (apiClient != null) {
            await syncTokenToBackend(token, apiClient: apiClient);
          }
        }
      } catch (te) {
        logDebug('FCM getToken non-blocking error: $te');
      }

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) async {
        await SecureStorageService().saveFCMToken(newToken);
        if (apiClient != null) {
          await syncTokenToBackend(newToken, apiClient: apiClient);
        }
      });

      _isInitialized = true;
    } catch (e) {
      logDebug('Error initializing FCM: $e');
    }
  }

  Future<void> syncTokenToBackend(String token, {ApiClient? apiClient}) async {
    try {
      final client = apiClient ?? ApiClient(secureStorage: SecureStorageService());
      final res = await client.post(
        ApiEndpoints.notificationsFcmToken,
        data: {'fcm_token': token},
      );
      logDebug('FCM Token successfully synced to backend! Result: $res');
    } catch (e) {
      // Normal if user is not logged in yet (unauthorized)
      logDebug('FCM Token sync postponed (user might not be logged in): $e');
    }
  }

  Future<void> syncStoredTokenIfLoggedIn({ApiClient? apiClient}) async {
    try {
      await _ensureFirebaseInitialized();
      if (!_isInitialized) {
        await initialize(apiClient: apiClient);
      }
      var token = await SecureStorageService().getFCMToken();
      if (token == null || token.isEmpty) {
        token = await _messaging.getToken().timeout(const Duration(seconds: 10));
        if (token != null && token.isNotEmpty) {
          await SecureStorageService().saveFCMToken(token);
        }
      }
      if (token != null && token.isNotEmpty) {
        await syncTokenToBackend(token, apiClient: apiClient);
      }
    } catch (e) {
      logDebug('Error syncing stored token: $e');
    }
  }
}

