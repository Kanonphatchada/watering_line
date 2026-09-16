import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../web_utils.dart';
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

        clearUrlQueryParams();

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
    final Uri url = Uri.parse('https://line-auth-server.onrender.com/login');

    if (!await launchUrl(url, mode: LaunchMode.platformDefault)) {
      throw 'Could not launch LINE Login';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1B5E20).withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.eco,
                  size: 48,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "WateringLine",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "ระบบรดน้ำต้นไม้อัตโนมัติ",
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: 240,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _loginWithLine,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF06C755),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.login),
                  label: const Text(
                    "Login with LINE",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
