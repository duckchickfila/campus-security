import 'package:flutter/material.dart';
import 'package:demo_app/student_side/demo_page.dart';
import 'package:demo_app/student_side/login_page.dart';
import 'package:demo_app/student_side/tutorial_pages.dart';
import 'package:demo_app/guard_side/main_page.dart';
import 'package:demo_app/guard_side/tutorial_pages.dart';
import 'package:demo_app/guard_side/sos_report_viewer.dart';   // notifications
import 'package:demo_app/student_side/chat_page.dart';         // ✅ NEW import
import 'package:supabase_flutter/supabase_flutter.dart';
import 'soshandler.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Local notifications
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// Define Android notification channel
const AndroidNotificationChannel sosChannel = AndroidNotificationChannel(
  'sos_channel',
  'SOS Alerts',
  description: 'High priority SOS notifications for guards',
  importance: Importance.max,
);

/// Show local notification (used for foreground messages)
void _showNotification(RemoteMessage message) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'sos_channel',
    'SOS Alerts',
    channelDescription: 'High priority SOS notifications for guards',
    importance: Importance.max,
    priority: Priority.high,
    ticker: 'ticker',
  );

  const NotificationDetails platformDetails =
      NotificationDetails(android: androidDetails);

  // ✅ Decide payload type (SOS vs Chat)
  final payload = message.data['sosId'] ?? message.data['chatId'];

  await flutterLocalNotificationsPlugin.show(
    0,
    message.notification?.title ?? '🚨 New Alert',
    message.notification?.body ?? 'You have a new message!',
    platformDetails,
    payload: payload,
  );
}

/// Background tap handler
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  final payload = response.payload;
  if (payload != null && payload.isNotEmpty) {
    debugPrint('📲 Background notification tapped with payload: $payload');
    // Optional: add navigation logic here
  }
}

/// Background handler for FCM
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("📡 Background handler fired");
  debugPrint("🔎 Full message payload (background isolate): ${message.toMap()}");
  // ❌ Do not call _showNotification here
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Initialize Firebase
  await Firebase.initializeApp();

  // ✅ Register background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // ✅ Request notification permissions
  final settings = await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  debugPrint('Notification permission status: ${settings.authorizationStatus}');

  // ✅ Initialize Supabase
  await Supabase.initialize(
    url: 'https://pvqkkfmzdjquqjxabzur.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB2cWtrZm16ZGpxdXFqeGFienVyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjYzOTQ0MzEsImV4cCI6MjA4MTk3MDQzMX0.V9V2SXbDt9mwWOQTaa_D_RW5puBxMVwtmhIqFG0ekvw',
  );

  // ✅ Initialize native SOS handler
  SOSHandler.init(navigatorKey);

  // ✅ Configure local notifications
  const AndroidInitializationSettings initSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initSettings =
      InitializationSettings(android: initSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) async {
      final payload = response.payload;
      if (payload != null && payload.isNotEmpty) {
        if (response.payload!.startsWith("chat_")) {
          final sosId = response.payload!.replaceFirst("chat_", "");
          final studentId = response.payload!.split("_").length > 2
              ? response.payload!.split("_")[2]
              : "";
          navigatorKey.currentState?.push(MaterialPageRoute(
            builder: (_) => ChatPage(
              sosId: sosId,
              guardId: Supabase.instance.client.auth.currentUser?.id ?? "",
              studentId: studentId,
            ),
          ));
        } else {
          navigatorKey.currentState?.push(MaterialPageRoute(
            builder: (_) => SosReportViewer(sosId: payload),
          ));
        }
      }
    },
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );

  // ✅ Create Android notification channel
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(sosChannel);

  // ✅ Foreground notifications
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint("📡 Foreground notification received");
    debugPrint("🔎 Full message payload (foreground): ${message.toMap()}");
    _showNotification(message);
  });

  // ✅ Handle notification taps when app is in background
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    debugPrint("Background notification tapped");

    final sosId = message.data['sosId'];
    final chatId = message.data['chatId'];
    final studentId = message.data['studentId'];

    if (chatId != null && chatId.isNotEmpty) {
      navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (_) => ChatPage(
          sosId: chatId,
          guardId: Supabase.instance.client.auth.currentUser?.id ?? "",
          studentId: studentId ?? "",
        ),
      ));
    } else if (sosId != null && sosId.isNotEmpty) {
      navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (_) => SosReportViewer(sosId: sosId),
      ));
    } else {
      debugPrint("⚠️ No valid payload in notification: ${message.data}");
    }
  });

  runApp(MyApp(navigatorKey: navigatorKey));

  // ✅ Handle notification when app is opened from terminated state
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sosId = initialMessage.data['sosId'];
      final chatId = initialMessage.data['chatId'];
      final studentId = initialMessage.data['studentId'];

      if (chatId != null && chatId.isNotEmpty) {
        navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (_) => ChatPage(
            sosId: chatId,
            guardId: Supabase.instance.client.auth.currentUser?.id ?? "",
            studentId: studentId ?? "",
          ),
        ));
      } else if (sosId != null && sosId.isNotEmpty) {
        navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (_) => SosReportViewer(sosId: sosId),
        ));
      }
    });
  }

  // ✅ Register FCM token in Supabase (student_details / guard_details)
  final fcmToken = await FirebaseMessaging.instance.getToken();
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (fcmToken != null && userId != null) {
    final supabase = Supabase.instance.client;

    final studentProfile = await supabase
        .from('student_details')
        .select('user_id')
        .eq('user_id', userId)
        .maybeSingle();

    if (studentProfile != null) {
      await supabase
          .from('student_details')
          .update({'fcm_token': fcmToken})
          .eq('user_id', userId);
      debugPrint("📡 FCM token registered for student $userId");
    } else {
      await supabase
          .from('guard_details')
          .update({'fcm_token': fcmToken})
          .eq('user_id', userId);
      debugPrint("📡 FCM token registered for guard $userId");
    }
  }
}

class MyApp extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  const MyApp({super.key, required this.navigatorKey});

  Future<Widget> _getHomeFuture() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return const LoginPage();

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return const LoginPage();

    final supabase = Supabase.instance.client;

    final studentProfile = await supabase
        .from('student_details')
        .select('seen_tutorial')
        .eq('user_id', userId)
        .maybeSingle();

    if (studentProfile != null) {
      final seenTutorial = studentProfile['seen_tutorial'] ?? false;
      return seenTutorial ? const Demopage1() : const TutorialPages();
    }

    final guardProfile = await supabase
        .from('guard_details')
        .select('seen_tutorial')
        .eq('user_id', userId)
        .maybeSingle();

    if (guardProfile != null) {
      final seenTutorial = guardProfile['seen_tutorial'] ?? false;
      return seenTutorial ? const GuardMainPage() : const GuardTutorialPages();
    }

    return const LoginPage();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _getHomeFuture(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const MaterialApp(
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          theme: ThemeData(
            primarySwatch: Colors.blue,
            fontFamily: 'Inter',
          ),
          home: snapshot.data,
        );
      },
    );
  }
}