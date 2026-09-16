import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'web_utils.dart';
import 'firebase_options.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'pages/add_device_page.dart';

const _brandGreen = Color(0xFF1B5E20);

/// Global theme-mode state so any page (e.g. the toggle button on
/// HomePage's AppBar) can flip light/dark without prop-drilling.
final ValueNotifier<ThemeMode> themeModeNotifier =
    ValueNotifier(ThemeMode.light);

const _themePrefKey = 'isDarkMode';

Future<void> toggleThemeMode() async {
  themeModeNotifier.value = themeModeNotifier.value == ThemeMode.dark
      ? ThemeMode.light
      : ThemeMode.dark;

  try {
    final prefs = await SharedPreferences.getInstance()
        .timeout(const Duration(seconds: 2));
    await prefs.setBool(
        _themePrefKey, themeModeNotifier.value == ThemeMode.dark);
  } catch (e) {
    print("⚠️ ไม่สามารถบันทึกค่าธีม: $e");
  }
}

Future<void> _loadThemeMode() async {
  // Never let a stuck/unavailable prefs backend block app startup —
  // fall back to the light theme if this doesn't resolve quickly.
  try {
    final prefs = await SharedPreferences.getInstance()
        .timeout(const Duration(seconds: 2));
    themeModeNotifier.value = (prefs.getBool(_themePrefKey) ?? false)
        ? ThemeMode.dark
        : ThemeMode.light;
  } catch (e) {
    print("⚠️ ไม่สามารถโหลดค่าธีมที่บันทึกไว้: $e");
  }
}

final ThemeData _appTheme = ThemeData(
  useMaterial3: true,
  colorSchemeSeed: const Color(0xFF2E7D32),
  scaffoldBackgroundColor: const Color(0xFFF3F8F3),
  textTheme: GoogleFonts.kanitTextTheme(),
  appBarTheme: AppBarTheme(
    backgroundColor: _brandGreen,
    foregroundColor: Colors.white,
    elevation: 0,
    shadowColor: Colors.black.withValues(alpha: 0.25),
    scrolledUnderElevation: 4,
    centerTitle: false,
    iconTheme: const IconThemeData(color: Colors.white),
    actionsIconTheme: const IconThemeData(color: Colors.white),
    titleTextStyle: GoogleFonts.kanit(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    ),
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    color: Colors.white,
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  ),
  dialogTheme: DialogThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
);

final ThemeData _appDarkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorSchemeSeed: const Color(0xFF2E7D32),
  scaffoldBackgroundColor: const Color(0xFF121212),
  textTheme: GoogleFonts.kanitTextTheme(
      ThemeData(brightness: Brightness.dark).textTheme),
  appBarTheme: AppBarTheme(
    backgroundColor: _brandGreen,
    foregroundColor: Colors.white,
    elevation: 0,
    shadowColor: Colors.black.withValues(alpha: 0.5),
    scrolledUnderElevation: 4,
    centerTitle: false,
    iconTheme: const IconThemeData(color: Colors.white),
    actionsIconTheme: const IconThemeData(color: Colors.white),
    titleTextStyle: GoogleFonts.kanit(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    ),
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    color: const Color(0xFF1E1E1E),
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFF1E1E1E),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: const Color(0xFF1E1E1E),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔥 Firebase.initializeApp() has been observed to hang indefinitely on
  // some browser/network combinations on web (a known FlutterFire issue).
  // Bound it with a timeout so the app always renders SOMETHING instead of
  // staying on a blank white page forever if that happens.
  bool firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 8));

    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
      webExperimentalForceLongPolling: true,
    );
    firebaseReady = true;
  } catch (e) {
    print("❌ Firebase initialization failed or timed out: $e");
  }

  await _loadThemeMode();

  runApp(MyApp(firebaseReady: firebaseReady));
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
  final bool firebaseReady;

  const MyApp({super.key, required this.firebaseReady});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.firebaseReady) {
      _handleAuth();
    }
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

        clearUrlQueryParams();
      } catch (e) {
        print("❌ LOGIN ERROR = $e");
      }
    } else {
      // 🔥 รอ Firebase restore session ที่เคย login ค้างไว้จริงๆ (แทนการเดา
      // ด้วย delay คงที่ ซึ่งถ้าเน็ต/เครื่องช้ากว่านั้นจะโดนเด้งออกจากระบบ
      // ทั้งที่จริงๆ ยัง login ค้างอยู่)
      try {
        await FirebaseAuth.instance
            .authStateChanges()
            .first
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        print("⚠️ ตรวจสอบสถานะ login ไม่ทันเวลา: $e");
      }
    }

    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.firebaseReady) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _appTheme,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    "เชื่อมต่อเซิร์ฟเวอร์ไม่สำเร็จ",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่อีกครั้ง",
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => reloadPage(),
                    icon: const Icon(Icons.refresh),
                    label: const Text("ลองใหม่"),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (isLoading) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    print("🔥 CURRENT USER = $user");

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _appTheme,
          darkTheme: _appDarkTheme,
          themeMode: mode,
          home: user != null ? const CheckDevicePage() : const LoginPage(),
        );
      },
    );
  }
}
