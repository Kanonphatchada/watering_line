const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

// เมื่อบอร์ด ESP32 ตัวใหม่สร้าง doc ของตัวเองขึ้นมา (ไม่ว่าจะเป็นตัวที่เท่าไหร่
// ในกลุ่มก็ตาม) ถ้ากลุ่มนั้นถูกลูกค้า claim ไปแล้ว ให้ผูก uid ของเจ้าของให้ทันที
// โดยอัตโนมัติ ไม่ต้องให้ลูกค้ากรอกรหัสซ้ำหรือให้ admin มาผูกมือ
//
// แยกไว้คนละที่กับ functions/ (submodule ของ line-auth-server บน Render)
// เพราะ deploy กันคนละระบบ ไม่เกี่ยวข้องกัน — ตัวนี้ deploy ขึ้น Firebase
// Cloud Functions เท่านั้น ไม่กระทบ Render เลย
exports.autoAssignDeviceOwner = functions.firestore
  .document("ESP32/{nanoId}")
  .onCreate(async (snap) => {
    const data = snap.data();
    const groupId = data.groupId;

    if (!groupId || data.uid) {
      return null;
    }

    const registryDoc = await admin
      .firestore()
      .collection("device_registry")
      .doc(groupId)
      .get();

    if (!registryDoc.exists) {
      return null;
    }

    const ownerUid = registryDoc.data().ownerUid;
    if (!ownerUid) {
      return null; // กลุ่มนี้ยังไม่มีใคร claim
    }

    return snap.ref.update({ uid: ownerUid });
  });

// อุปกรณ์ควรรายงานค่าเข้ามาสม่ำเสมอ ถ้าเงียบไปนานผิดปกติ น่าจะพัง/หลุดการ
// เชื่อมต่อ — ปรับตามความถี่จริงที่บอร์ดควรรายงานค่า
const OFFLINE_THRESHOLD_MS = 30 * 60 * 1000; // 30 นาที

// ทุกครั้งที่ ESP32 doc ถูกสร้าง/แก้ไข เช็คว่าเป็นการเปลี่ยนแปลงจากตัวบอร์ด
// จริงไหม (Moisture/Time คือ field ที่มีแต่บอร์ดเขียนได้ ตาม firestore rules
// — ต่างจาก Auto/Automois/Valve ที่ผู้ใช้ในแอปกดเองได้) ถ้าใช่ ให้ประทับเวลา
// "เห็นบอร์ดล่าสุด" และล้างสถานะ offline ทันที (มาออนไลน์ปุ๊บ หายปุ๊บ ไม่ต้อง
// รอรอบ scheduled ถัดไป) พร้อมจับเวลาทุกครั้งที่ Valve เปลี่ยนสถานะ ไว้ให้
// flagValveFaults ข้างล่างใช้เช็คว่าคำสั่งวาล์วนิ่งพอจะสรุปผลหรือยัง
exports.trackDeviceLastSeen = functions.firestore
  .document("ESP32/{nanoId}")
  .onWrite(async (change) => {
    if (!change.after.exists) {
      return null; // doc ถูกลบ ไม่ต้องทำอะไร
    }

    const after = change.after.data();
    const before = change.before.exists ? change.before.data() : null;

    const isFirstWrite = !before;
    const reportedNewReading =
      isFirstWrite ||
      before.Moisture !== after.Moisture ||
      before.Time !== after.Time;

    const updates = {};

    if (reportedNewReading) {
      updates.lastSeen = admin.firestore.FieldValue.serverTimestamp();
      updates.offline = false;
    }

    if (isFirstWrite || before.Valve !== after.Valve) {
      updates.valveChangedAt = admin.firestore.FieldValue.serverTimestamp();
    }

    if (Object.keys(updates).length === 0) {
      return null;
    }

    return change.after.ref.update(updates);
  });

// เช็คทุกอุปกรณ์เป็นระยะ ถ้าไม่มีการรายงานค่าเกินเวลาที่กำหนด ตั้ง
// offline: true ให้แอปโชว์เตือนผู้ใช้ว่าอุปกรณ์อาจเสีย/ขาดการเชื่อมต่อ
// (การกลับมาออนไลน์ไม่ต้องรอฟังก์ชันนี้ — trackDeviceLastSeen ข้างบน
// จะล้างสถานะให้ทันทีที่บอร์ดกลับมารายงานค่าอีกครั้ง)
exports.flagOfflineDevices = functions.pubsub
  .schedule("every 15 minutes")
  .onRun(async () => {
    const cutoff = admin.firestore.Timestamp.fromMillis(
      Date.now() - OFFLINE_THRESHOLD_MS
    );

    const snapshot = await admin
      .firestore()
      .collection("ESP32")
      .where("lastSeen", "<", cutoff)
      .get();

    const batch = admin.firestore().batch();
    let staleCount = 0;

    snapshot.forEach((doc) => {
      if (doc.data().offline !== true) {
        batch.update(doc.ref, { offline: true });
        staleCount++;
      }
    });

    if (staleCount > 0) {
      await batch.commit();
    }

    return null;
  });

// เซ็นเซอร์ที่ใช้ (RS485 วัดความชื้นดิน) รายงานเป็น % ความชื้น มาตรฐานเดียวกัน
// ทุกตัว ความคลาดเคลื่อนของตัวเซ็นเซอร์เองอยู่ที่ประมาณ ±2-3% ตามสเปก เลยตั้ง
// พื้นที่ให้ถือว่า "ค่านิ่ง/ไม่ขยับ" ถ้าเปลี่ยนไม่เกินนี้ กันไม่ให้สัญญาณรบกวน
// เล็กๆ ของเซ็นเซอร์ทำให้แจ้งเตือนผิด (false alarm)
const MOISTURE_NOISE_FLOOR_PERCENT = 3;

// ต้องรอให้คำสั่งวาล์วนิ่ง (ไม่เพิ่งสั่งเปลี่ยน) มานานพอจะดูแนวโน้มได้จริง —
// ใช้ระยะเวลาเดียวกับ threshold ขาดการติดต่อ เพื่อให้มีข้อมูลอย่างน้อย ~6 ค่า
// (บอร์ดรายงานทุก 5 นาที)
const VALVE_STABLE_MS = 30 * 60 * 1000; // 30 นาที

// เช็คว่าคำสั่งวาล์วกับแนวโน้มความชื้นจริงไปคนละทิศกันไหม:
// - สั่งปิดน้ำแล้ว (Valve: false) แต่ความชื้นยังพุ่งขึ้นต่อเนื่อง → วาล์วค้างเปิด
// - สั่งเปิดน้ำแล้ว (Valve: true) แต่ความชื้นไม่ขยับขึ้นเลย → วาล์ว/ปั๊มอาจไม่ทำงาน
// ไม่เช็คอุปกรณ์ที่ offline อยู่แล้ว (ไม่มีข้อมูลใหม่มาเทียบอยู่แล้ว ไม่ต้องซ้ำ)
exports.flagValveFaults = functions.pubsub
  .schedule("every 15 minutes")
  .onRun(async () => {
    const stableCutoff = admin.firestore.Timestamp.fromMillis(
      Date.now() - VALVE_STABLE_MS
    );

    const snapshot = await admin
      .firestore()
      .collection("ESP32")
      .where("valveChangedAt", "<=", stableCutoff)
      .get();

    const batch = admin.firestore().batch();
    let updateCount = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();

      if (data.offline === true) {
        continue;
      }

      const logsSnap = await doc.ref
        .collection("Logs")
        .where("timestamp", ">=", stableCutoff)
        .orderBy("timestamp", "asc")
        .get();

      const readings = logsSnap.docs
        .map((d) => d.data().moisture)
        .filter((m) => typeof m === "number");

      if (readings.length < 2) {
        continue; // ข้อมูลไม่พอจะสรุปแนวโน้มในช่วงนี้
      }

      const delta = readings[readings.length - 1] - readings[0];
      const valveOpen = data.Valve === true;

      let faultType = null;
      if (!valveOpen && delta > MOISTURE_NOISE_FLOOR_PERCENT) {
        faultType = "valve_stuck_open";
      } else if (valveOpen && delta < MOISTURE_NOISE_FLOOR_PERCENT) {
        faultType = "valve_no_flow";
      }

      const currentFault = data.faultType || null;
      if (currentFault !== faultType) {
        batch.update(doc.ref, {
          faultType: faultType || admin.firestore.FieldValue.delete(),
        });
        updateCount++;
      }
    }

    if (updateCount > 0) {
      await batch.commit();
    }

    return null;
  });
