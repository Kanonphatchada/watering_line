import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("🌱 My Watering System"),
      ),
      body: Center(
        child: Text(
          "ยินดีต้อนรับ ${user?.displayName ?? "User"}",
          style: const TextStyle(fontSize: 22),
        ),
      ),
    );
  }
}