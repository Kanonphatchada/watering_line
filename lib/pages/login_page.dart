import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:html' as html;
import 'home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {

  @override
  void initState() {
    super.initState();
    _handleLoginFromURL();
  }

  Future<void> _handleLoginFromURL() async {
    await Future.delayed(const Duration(milliseconds: 500));

    final uri = Uri.base;
    final token = uri.queryParameters['firebaseToken'];

    if (token != null && token.isNotEmpty) {
      try {
        await FirebaseAuth.instance.signInWithCustomToken(token);

        final user = FirebaseAuth.instance.currentUser;

        final displayName = uri.queryParameters['displayName'];
        final photoUrl = uri.queryParameters['pictureUrl'];

        if (displayName != null && displayName.isNotEmpty) {
          await user?.updateDisplayName(displayName);
        }

        if (photoUrl != null && photoUrl.isNotEmpty) {
          await user?.updatePhotoURL(photoUrl);
        }

        html.window.history.replaceState(null, '', '/');

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      } catch (e) {
        print("❌ Login error: $e");
      }
    }
  }

  Future<void> _loginWithLine() async {
    final Uri url =
        Uri.parse('https://line-auth-server.onrender.com/login');

    if (!await launchUrl(url, mode: LaunchMode.platformDefault)) {
      throw 'Could not launch LINE Login';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: _loginWithLine,
          child: const Text("Login with LINE"),
          
        ),
      ),
    );
  }
}