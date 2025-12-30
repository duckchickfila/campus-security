import 'package:flutter/material.dart';
import 'package:demo_app/demo_page.dart';
import 'package:demo_app/login_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'soshandler.dart';
import 'tutorial_pages.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://pvqkkfmzdjquqjxabzur.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB2cWtrZm16ZGpxdXFqeGFienVyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjYzOTQ0MzEsImV4cCI6MjA4MTk3MDQzMX0.V9V2SXbDt9mwWOQTaa_D_RW5puBxMVwtmhIqFG0ekvw',
  );

  SOSHandler.init(navigatorKey);

  runApp(MyApp(navigatorKey: navigatorKey));
}

class MyApp extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  const MyApp({super.key, required this.navigatorKey});

  Future<Widget> _getHome() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return const LoginPage();

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return const LoginPage();

    final profile = await Supabase.instance.client
        .from('student_details')
        .select('seen_tutorial')
        .eq('user_id', userId)
        .maybeSingle();

    final seenTutorial = profile?['seen_tutorial'] ?? false;
    return seenTutorial ? const Demopage1() : const TutorialPages();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _getHome(),
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