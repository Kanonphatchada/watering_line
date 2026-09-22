import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../auth/pages/login_page.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../main.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameController = TextEditingController();
  bool isLoading = true;
  bool isSaving = false;
  String? photoUrl;

  // การตั้งค่าว่าจะรับแจ้งเตือน LINE ประเภทไหนบ้าง — เก็บไว้ที่
  // users/{uid} ยังไม่เคยตั้งค่ามาก่อนถือว่าเปิดรับไว้ก่อน (default true)
  // ให้ตรงกับพฤติกรรมเดิมของผู้ใช้ที่มีอยู่แล้ว (ดู sendLineAlert ฝั่ง
  // checkDevices.js)
  bool _notifyOffline = true;
  bool _notifyFault = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => isLoading = false);
      return;
    }

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = doc.data();

    final name = data?['displayName'] ??
        user.displayName ??
        user.email?.split('@')[0] ??
        "User";

    if (!mounted) return;
    setState(() {
      _nameController.text = name;
      photoUrl = data?['pictureUrl'] ?? user.photoURL;
      _notifyOffline = data?['notifyOffline'] ?? true;
      _notifyFault = data?['notifyFault'] ?? true;
      isLoading = false;
    });
  }

  Future<void> _updateNotifyPref(String field, bool value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      if (field == 'notifyOffline') {
        _notifyOffline = value;
      } else {
        _notifyFault = value;
      }
    });

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      {field: value},
      SetOptions(merge: true),
    );
  }

  Future<void> _saveName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final newName = _nameController.text.trim();
    if (newName.isEmpty) return;

    setState(() => isSaving = true);

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      {'displayName': newName},
      SetOptions(merge: true),
    );

    if (!mounted) return;
    setState(() => isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2E7D32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        content: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Text(
              "บันทึกชื่อแล้ว",
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("ยืนยัน"),
        content: const Text("ต้องการออกจากระบบหรือไม่"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("ยกเลิก"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("ออก"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await FirebaseAuth.instance.signOut();

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.person_rounded),
            SizedBox(width: 8),
            Text("โปรไฟล์ผู้ใช้"),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : user == null
              ? const Center(child: Text("ไม่พบข้อมูลผู้ใช้"))
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Center(child: Avatar(photoUrl: photoUrl, size: 96)),
                        const SizedBox(height: 20),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "ชื่อที่แสดง",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.textTheme.bodySmall?.color,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _nameController,
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          prefixIcon:
                                              Icon(Icons.badge_outlined),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      height: 44,
                                      child: ElevatedButton(
                                        onPressed: isSaving ? null : _saveName,
                                        child: isSaving
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : const Text("บันทึก"),
                                      ),
                                    ),
                                  ],
                                ),
                                if (user.email != null) ...[
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Icon(Icons.mail_outline,
                                          size: 18,
                                          color:
                                              theme.textTheme.bodySmall?.color),
                                      const SizedBox(width: 8),
                                      Text(
                                        user.email!,
                                        style: TextStyle(
                                          color:
                                              theme.textTheme.bodySmall?.color,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Column(
                            children: [
                              const Padding(
                                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                                child: Row(
                                  children: [
                                    Text(
                                      "การแจ้งเตือน",
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SwitchListTile(
                                secondary: const Icon(Icons.cloud_off),
                                title: const Text("ขาดการติดต่อ"),
                                subtitle: const Text(
                                  "แจ้งเตือนเมื่ออุปกรณ์เงียบเกิน 30 นาที",
                                ),
                                value: _notifyOffline,
                                onChanged: (v) =>
                                    _updateNotifyPref('notifyOffline', v),
                              ),
                              SwitchListTile(
                                secondary:
                                    const Icon(Icons.report_problem_outlined),
                                title: const Text("อุปกรณ์ทำงานผิดปกติ"),
                                subtitle: const Text(
                                  "วาล์ว, เซนเซอร์ หรือ Nano มีปัญหา",
                                ),
                                value: _notifyFault,
                                onChanged: (v) =>
                                    _updateNotifyPref('notifyFault', v),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // ย้ายมาจากหน้าหลัก — ปุ่มสลับโหมดมืด/สว่างเคยอยู่ใน
                        // AppBar ของหน้าหลัก แต่ไปแย่งที่กับชื่อหน้า "หน้าหลัก"
                        // จนดูแน่นเกินไป ย้ายมาไว้ในโปรไฟล์แทน
                        Card(
                          child: ValueListenableBuilder<ThemeMode>(
                            valueListenable: themeModeNotifier,
                            builder: (context, mode, _) {
                              return SwitchListTile(
                                secondary: Icon(
                                  mode == ThemeMode.dark
                                      ? Icons.dark_mode
                                      : Icons.light_mode,
                                ),
                                title: const Text("โหมดมืด"),
                                value: mode == ThemeMode.dark,
                                onChanged: (_) => toggleThemeMode(),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Column(
                            children: [
                              const ListTile(
                                leading: Icon(Icons.login),
                                title: Text("เข้าสู่ระบบด้วย"),
                                trailing: Text("LINE"),
                              ),
                              const Divider(height: 1),
                              StreamBuilder<QuerySnapshot>(
                                stream: FirebaseFirestore.instance
                                    .collection('ESP32')
                                    .where('uid', isEqualTo: user.uid)
                                    .snapshots(),
                                builder: (context, snapshot) {
                                  final count = snapshot.data?.docs.length ?? 0;
                                  return ListTile(
                                    leading: const Icon(Icons.sensors),
                                    title: const Text("อุปกรณ์ที่เชื่อมต่อ"),
                                    trailing: Text("$count เครื่อง"),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                            ),
                            onPressed: _confirmLogout,
                            icon: const Icon(Icons.logout),
                            label: const Text("ออกจากระบบ"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
