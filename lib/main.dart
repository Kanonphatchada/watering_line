import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:html' as html;
import 'firebase_options.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'pages/add_device_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
    webExperimentalForceLongPolling: true,
  );

  runApp(const MyApp());
}

class CheckDevicePage extends StatelessWidget {
  const CheckDevicePage({super.key});

  Future<bool> hasDevice() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final query = await FirebaseFirestore.instance
        .collection('device_registry')
        .where('ownerUid', isEqualTo: uid)
        .get();

    return query.docs.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: hasDevice(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.data!) {
          return const HomePage();
        } else {
          return const AddDevicePage();
        }
      },
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _handleAuth();
  }

  Future<void> _handleAuth() async {
    print("🔥 FULL URL = ${Uri.base}");

    final uri = Uri.base;
    final token = uri.queryParameters['firebaseToken'];

    print("🔥 TOKEN = $token");

    if (token != null && token.isNotEmpty) {
      try {
        await FirebaseAuth.instance.signInWithCustomToken(token);

        final uid = FirebaseAuth.instance.currentUser?.uid;
        print("🔥 LOGIN UID = $uid");

        html.window.history.replaceState(null, '', '/');
      } catch (e) {
        print("❌ LOGIN ERROR = $e");
      }
    }

    // 🔥 รอ Firebase restore session
    await Future.delayed(const Duration(milliseconds: 500));

    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    print("🔥 CURRENT USER = $user");

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: user != null ? const CheckDevicePage() : const LoginPage(),
    );
  }
}
