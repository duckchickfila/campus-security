import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:demo_app/guard_side/sos_report_viewer.dart';

class NotificationHandler {
  static late GlobalKey<NavigatorState> _navigatorKey;
  static final _supabase = Supabase.instance.client;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Initialize notification handling
  static Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    _navigatorKey = navigatorKey;

    // ✅ Initialize local notifications
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings =
        InitializationSettings(android: androidInit, iOS: iosInit);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null && response.payload!.isNotEmpty) {
          final sosId = response.payload!;
          _navigatorKey.currentState?.push(
            MaterialPageRoute(builder: (_) => SosReportViewer(sosId: sosId)),
          );
        }
      },
    );

    // ✅ Capture and persist FCM token for this guard
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _supabase
            .from('guard_details')
            .update({'fcm_token': token})
            .eq('user_id', userId);
      }

      // Keep DB in sync if token refreshes
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        await _supabase
            .from('guard_details')
            .update({'fcm_token': newToken})
            .eq('user_id', userId);
      });
    }

    // ✅ Supabase realtime subscription for in-app alerts
    _supabase
        .channel('sos_reports')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'sos_reports',
          callback: (payload) {
            final sosId = payload.newRecord['id'].toString();
            showNotification(
              "🚨 New SOS Alert",
              "Tap to view details",
              sosId,
            );
          },
        )
        .subscribe();

    // ✅ FCM foreground handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final sosId = message.data['sosId'];
      if (sosId != null) {
        showNotification(
          "🚨 New SOS Alert",
          "Tap to view details",
          sosId,
        );
      }
    });

    // ✅ FCM notification tap handler
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final sosId = message.data['sosId'];
      if (sosId != null) {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => SosReportViewer(sosId: sosId)),
        );
      }
    });
  }

  /// Public method to show a local notification with deep-link payload
  static Future<void> showNotification(
      String title, String body, String sosId) async {
    const androidDetails = AndroidNotificationDetails(
      'sos_channel',
      'SOS Alerts',
      channelDescription: 'Notifications for SOS reports',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'SOS Alert',
    );

    const platformDetails = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      0,
      title,
      body,
      platformDetails,
      payload: sosId,
    );
  }
}