import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../network/api_client.dart';
import '../constants/api_endpoints.dart';
import '../security/secure_storage_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    debugPrint('FCM Background message: ${message.messageId} - ${message.notification?.title}');
  } catch (e) {
    debugPrint('FCM background error: $e');
  }
}

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'dmb_notification_channel',
    'Notifikasi Bank DMB',
    description: 'Kanal resmi notifikasi transaksi dan informasi PT BPR Dana Mandiri Bogor',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  bool _isInitialized = false;

  Future<void> initialize({ApiClient? apiClient}) async {
    if (_isInitialized) return;

    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Request permission on iOS / Android 13+
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint('FCM Permission status: ${settings.authorizationStatus}');

      // Setup Local Notifications for Foreground display
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          debugPrint('Local notification clicked: ${response.payload}');
        },
      );

      // Create Android Notification Channel
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      // Foreground message listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('FCM Foreground message: ${message.notification?.title}');
        final notification = message.notification;

        if (notification != null) {
          _localNotifications.show(
            notification.hashCode,
            notification.title,
            notification.body,
            NotificationDetails(
              android: AndroidNotificationDetails(
                _channel.id,
                _channel.name,
                channelDescription: _channel.description,
                icon: '@mipmap/ic_launcher',
                importance: Importance.high,
                priority: Priority.high,
                playSound: true,
                enableVibration: true,
              ),
              iOS: const DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
            ),
            payload: message.data['route'] ?? message.data['category'] ?? '',
          );
        }
      });

      // App opened from background by clicking notification
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('FCM opened app from notification: ${message.data}');
      });

      // Check initial message if app opened from terminated state
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('FCM launched app from terminated: ${initialMessage.data}');
      }

      // Get FCM Device Token
      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        debugPrint('FCM Device Token: $token');
        await SecureStorageService().saveFCMToken(token);
        if (apiClient != null) {
          await syncTokenToBackend(token, apiClient: apiClient);
        }
      }

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) async {
        debugPrint('FCM Token refreshed: $newToken');
        await SecureStorageService().saveFCMToken(newToken);
        if (apiClient != null) {
          await syncTokenToBackend(newToken, apiClient: apiClient);
        }
      });

      _isInitialized = true;
    } catch (e) {
      debugPrint('Error initializing FCM: $e');
    }
  }

  Future<void> syncTokenToBackend(String token, {ApiClient? apiClient}) async {
    try {
      final client = apiClient ?? ApiClient();
      await client.post(
        ApiEndpoints.notificationsFcmToken,
        data: {'fcm_token': token},
      );
      debugPrint('FCM Token successfully synced to backend!');
    } catch (e) {
      // Normal if user is not logged in yet (unauthorized)
      debugPrint('FCM Token sync postponed (user might not be logged in): $e');
    }
  }

  Future<void> syncStoredTokenIfLoggedIn({ApiClient? apiClient}) async {
    try {
      final token = await SecureStorageService().getFCMToken();
      if (token != null && token.isNotEmpty) {
        await syncTokenToBackend(token, apiClient: apiClient);
      }
    } catch (_) {}
  }
}
