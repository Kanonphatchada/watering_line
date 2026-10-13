import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

// "อุปกรณ์ของฉัน" = อุปกรณ์ที่ตัวเองเป็นเจ้าของ (uid) + อุปกรณ์ของฟาร์มที่ถูกเชิญ
// เป็นสมาชิก (memberUids) — รวมสองคำค้นเพราะอุปกรณ์เก่ายังไม่มี memberUids จนกว่า
// backend จะซิงก์รายชื่อให้ (ทำเองทุก 10 นาที) และ Firestore rules ให้ค้นได้
// เฉพาะแบบที่พิสูจน์ได้ว่าเป็นของผู้ใช้ จึงรวมสองคำค้นฝั่งแอป
Stream<List<QueryDocumentSnapshot>> watchMyDevices(String uid) {
  final db = FirebaseFirestore.instance.collection('ESP32');
  return mergeLatestById<QueryDocumentSnapshot>(
    db.where('uid', isEqualTo: uid).snapshots().map((s) => s.docs),
    db.where('memberUids', arrayContains: uid).snapshots().map((s) => s.docs),
    (d) => d.id,
  );
}

// ครั้งเดียว (ไม่ติดตามต่อ) — ใช้ตอนกดกระดิ่งแจ้งเตือน
Future<List<QueryDocumentSnapshot>> getMyDevices(String uid) async {
  final db = FirebaseFirestore.instance.collection('ESP32');
  final results = await Future.wait([
    db.where('uid', isEqualTo: uid).get(),
    db.where('memberUids', arrayContains: uid).get(),
  ]);
  return _mergeById<QueryDocumentSnapshot>(
    results[0].docs,
    results[1].docs,
    (d) => d.id,
  );
}

List<T> _mergeById<T>(List<T> a, List<T> b, String Function(T) idOf) {
  final byId = <String, T>{};
  for (final item in [...a, ...b]) {
    byId.putIfAbsent(idOf(item), () => item);
  }
  final ids = byId.keys.toList()..sort();
  return [for (final id in ids) byId[id] as T];
}

// รวมสองสตรีมรายการ: ส่งค่าออกเมื่อทั้งสองสตรีมส่งค่าแรกมาแล้ว และทุกครั้งที่
// สตรีมใดสตรีมหนึ่งเปลี่ยน รายการเดียวกัน (id ซ้ำ) นับครั้งเดียว เรียงตาม id
// error จากสตรีมใดก็ส่งต่อออกไป ยกเลิกการฟังทั้งคู่เมื่อผู้ฟังยกเลิก
Stream<List<T>> mergeLatestById<T>(
  Stream<List<T>> a,
  Stream<List<T>> b,
  String Function(T) idOf,
) {
  late StreamController<List<T>> controller;
  StreamSubscription<List<T>>? subA;
  StreamSubscription<List<T>>? subB;
  List<T>? latestA;
  List<T>? latestB;

  void emit() {
    final x = latestA;
    final y = latestB;
    if (x == null || y == null || controller.isClosed) return;
    controller.add(_mergeById(x, y, idOf));
  }

  controller = StreamController<List<T>>(
    onListen: () {
      subA = a.listen(
        (v) {
          latestA = v;
          emit();
        },
        onError: controller.addError,
      );
      subB = b.listen(
        (v) {
          latestB = v;
          emit();
        },
        onError: controller.addError,
      );
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
    },
  );
  return controller.stream;
}

// "ฟาร์มของฉัน" (device_registry) = ฟาร์มที่เป็นเจ้าของ (ownerUid) + ฟาร์มที่ถูกเชิญ
// เป็นสมาชิก (memberUids) — รวมสองคำค้นด้วยเหตุผลเดียวกับ watchMyDevices
Stream<List<QueryDocumentSnapshot>> watchMyFarms(String uid) {
  final db = FirebaseFirestore.instance.collection('device_registry');
  return mergeLatestById<QueryDocumentSnapshot>(
    db.where('ownerUid', isEqualTo: uid).snapshots().map((s) => s.docs),
    db.where('memberUids', arrayContains: uid).snapshots().map((s) => s.docs),
    (d) => d.id,
  );
}

Future<List<QueryDocumentSnapshot>> getMyFarms(String uid) async {
  final db = FirebaseFirestore.instance.collection('device_registry');
  final results = await Future.wait([
    db.where('ownerUid', isEqualTo: uid).get(),
    db.where('memberUids', arrayContains: uid).get(),
  ]);
  return _mergeById<QueryDocumentSnapshot>(
    results[0].docs,
    results[1].docs,
    (d) => d.id,
  );
}
