import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

// ระบบสมาชิกของฟาร์ม (ฝั่งแอป) — หลายคนใช้ฟาร์มเดียวกัน เจ้าของตั้งสิทธิ์รายคน
// เชิญ/เข้าร่วม/ปรับสิทธิ์/ลบ/ออก ทำผ่าน backend (Admin SDK) ทั้งหมด แอปเขียน
// ฟิลด์สมาชิกลง Firestore เองไม่ได้ตาม rules
//
// สิทธิ์มี 3 ระดับ (settings ต้องมาคู่กับ control เสมอ เพราะการบันทึกตารางเวลา
// เขียนทั้งฟิลด์ตารางเวลาและ Auto/Valve พร้อมกัน — backend บังคับให้เหมือนกัน)

enum MemberLevel { viewer, controller, manager }

MemberLevel levelOf({required bool control, required bool settings}) => settings
    ? MemberLevel.manager
    : control
        ? MemberLevel.controller
        : MemberLevel.viewer;

({bool control, bool settings}) flagsOf(MemberLevel level) => (
      control: level != MemberLevel.viewer,
      settings: level == MemberLevel.manager,
    );

String levelLabel(MemberLevel level) => switch (level) {
      MemberLevel.viewer => "ดูอย่างเดียว",
      MemberLevel.controller => "ควบคุมได้",
      MemberLevel.manager => "จัดการได้",
    };

String levelDescription(MemberLevel level) => switch (level) {
      MemberLevel.viewer =>
        "ดูค่าความชื้นและสถานะอุปกรณ์ได้ ไม่มีสิทธิ์สั่งงานหรือแก้ไขอะไร",
      MemberLevel.controller =>
        "ดูได้ + เปิด/ปิดวาล์ว สลับโหมดอัตโนมัติ และตั้งความชื้นเป้าหมาย",
      MemberLevel.manager =>
        "ควบคุมได้ + ตั้งตารางเวลารดน้ำ ข้ามรดน้ำเมื่อฝนตก และตำแหน่งฟาร์ม",
    };

// สิทธิ์ของผู้ใช้บนอุปกรณ์หนึ่งตัว อ่านจากเอกสารอุปกรณ์ — เจ้าของ (uid) ได้ทุกสิทธิ์
// เสมอ แม้ backend ยังไม่ได้ซิงก์รายชื่อสิทธิ์ให้เอกสารนั้น (ฟาร์มเก่า) ตรงกับที่
// Firestore rules ใช้ตัดสินจริง
bool isDeviceOwner(Map<String, dynamic> device, String? uid) =>
    uid != null && device['uid'] == uid;

bool _inList(Map<String, dynamic> device, String key, String? uid) {
  final list = device[key];
  return uid != null && list is List && list.contains(uid);
}

bool canControlDevice(Map<String, dynamic> device, String? uid) =>
    isDeviceOwner(device, uid) || _inList(device, 'controlUids', uid);

bool canSettingsDevice(Map<String, dynamic> device, String? uid) =>
    isDeviceOwner(device, uid) || _inList(device, 'settingsUids', uid);

// สิทธิ์ระดับฟาร์ม (เอกสาร device_registry) — ใช้กับหน้าตั้งค่าฟาร์ม
bool canSettingsFarm(Map<String, dynamic> registry, String? uid) =>
    uid != null &&
    (registry['ownerUid'] == uid || _inList(registry, 'settingsUids', uid));

class FarmMember {
  final String uid;
  final String name;
  final MemberLevel level;
  final DateTime? joinedAt;

  const FarmMember({
    required this.uid,
    required this.name,
    required this.level,
    this.joinedAt,
  });

  // อ่านรายชื่อจากฟิลด์ members ของเอกสารฟาร์ม — ข้ามรายการที่รูปแบบผิด
  // เรียงตามเวลาเข้าร่วม (เก่าสุดก่อน)
  static List<FarmMember> parseAll(Map<String, dynamic>? registry) {
    final raw = registry?['members'];
    if (raw is! Map) return const [];
    final result = <FarmMember>[];
    raw.forEach((key, value) {
      if (key is! String || value is! Map) return;
      final joined = value['joinedAt'];
      result.add(FarmMember(
        uid: key,
        name: value['name'] is String ? value['name'] as String : '',
        level: levelOf(
          control: value['control'] == true,
          settings: value['settings'] == true,
        ),
        joinedAt: joined is num
            ? DateTime.fromMillisecondsSinceEpoch(joined.toInt())
            : null,
      ));
    });
    result.sort((a, b) {
      final x = a.joinedAt?.millisecondsSinceEpoch ?? 0;
      final y = b.joinedAt?.millisecondsSinceEpoch ?? 0;
      return x != y ? x.compareTo(y) : a.uid.compareTo(b.uid);
    });
    return result;
  }
}

class FarmApiException implements Exception {
  final String message;
  const FarmApiException(this.message);

  @override
  String toString() => message;
}

const _backend = "https://line-auth-server.onrender.com";

// backend เป็น Render free tier — ตื่นครั้งแรก (cold start) ใช้เวลาได้ถึง 30-60
// วิ จึงรอได้นาน ข้อความ error จาก backend เป็นภาษาไทยพร้อมแสดงต่อผู้ใช้ได้เลย
Future<Map<String, dynamic>> _post(
    String path, Map<String, dynamic> body) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw const FarmApiException("ยังไม่ได้เข้าสู่ระบบ");
  try {
    final idToken = await user.getIdToken();
    final res = await http
        .post(
          Uri.parse("$_backend$path"),
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $idToken",
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      final text = utf8.decode(res.bodyBytes).trim();
      throw FarmApiException(
        text.isNotEmpty && text.length < 200
            ? text
            : "ทำรายการไม่สำเร็จ ลองใหม่อีกครั้ง",
      );
    }
    final decoded = jsonDecode(res.body);
    return decoded is Map<String, dynamic> ? decoded : {};
  } on TimeoutException {
    throw const FarmApiException(
      "เชื่อมต่อ server ไม่ได้ (server อาจกำลัง sleep) ลองใหม่อีกครั้ง",
    );
  } on FarmApiException {
    rethrow;
  } catch (_) {
    throw const FarmApiException("ทำรายการไม่สำเร็จ ลองใหม่อีกครั้ง");
  }
}

class FarmInvite {
  final String code;
  final DateTime expiresAt;
  const FarmInvite(this.code, this.expiresAt);
}

Future<FarmInvite> createFarmInvite(String farmId, MemberLevel level) async {
  final f = flagsOf(level);
  final json = await _post("/farm/invite", {
    "farmId": farmId,
    "control": f.control,
    "settings": f.settings,
  });
  return FarmInvite(
    json["code"] as String,
    DateTime.fromMillisecondsSinceEpoch((json["expiresAt"] as num).toInt()),
  );
}

// คืน farmId ที่เข้าร่วม
Future<String> joinFarm(String code) async {
  final json = await _post("/farm/join", {"code": code});
  return json["farmId"] as String;
}

Future<void> setMemberLevel(
  String farmId,
  String memberUid,
  MemberLevel level,
) async {
  final f = flagsOf(level);
  await _post("/farm/members/update", {
    "farmId": farmId,
    "memberUid": memberUid,
    "control": f.control,
    "settings": f.settings,
  });
}

Future<void> removeFarmMember(String farmId, String memberUid) =>
    _post("/farm/members/remove", {"farmId": farmId, "memberUid": memberUid});

Future<void> leaveFarm(String farmId) =>
    _post("/farm/leave", {"farmId": farmId});
