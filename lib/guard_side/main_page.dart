import 'package:flutter/material.dart';
import 'package:demo_app/guard_side/custom_appbar.dart';

class GuardMainPage extends StatelessWidget {
  const GuardMainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GuardCustomAppBar(),
      body: const Center(
        child: Text("Guard Main Page"),
      ),
    );
  }
}