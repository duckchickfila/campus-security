import 'package:flutter/material.dart';
import 'package:demo_app/demo_page.dart'; // your main screen
import 'package:demo_app/login_page.dart'; // ✅ your login page
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://pvqkkfmzdjquqjxabzur.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB2cWtrZm16ZGpxdXFqeGFienVyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjYzOTQ0MzEsImV4cCI6MjA4MTk3MDQzMX0.V9V2SXbDt9mwWOQTaa_D_RW5puBxMVwtmhIqFG0ekvw',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // ✅ If no session, show LoginPage; else show Demopage1
      home: session == null ? const LoginPage() : const Demopage1(),
    );
  }
}