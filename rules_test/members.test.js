// ทดสอบกฎรอบสมาชิกของฟาร์ม: สมาชิก 3 ระดับ (ดูอย่างเดียว / ควบคุม / จัดการ) บนฟาร์ม
// FarmA ของ alice — viewer ดูอย่างเดียว, driver ควบคุมได้, manager ควบคุม+ตั้งค่าได้
// รายชื่อสิทธิ์ (memberUids/controlUids/settingsUids) เขียนโดย backend (Admin SDK)
// ในเทสต์นี้ใส่ไว้ในข้อมูลตั้งต้นตรงๆ
import {
  useRules,
  test,
  assertSucceeds,
  assertFails,
  doc,
  getDoc,
  updateDoc,
  setDoc,
  collection,
  query,
  where,
  getDocs,
} from "./shared.js";

const access = {
  memberUids: ["alice", "viewer", "driver", "manager"],
  controlUids: ["alice", "driver", "manager"],
  settingsUids: ["alice", "manager"],
};

const c = useRules(
  new URL("../firestore.rules", import.meta.url),
  "demo-rules-members",
  async (db) => {
    await setDoc(doc(db, "ESP32/Nano1"), {
      uid: "alice",
      groupId: "FarmA",
      Moisture: 30,
      Automois: 20,
      Valve: false,
      Auto: true,
      ...access,
    });
    await setDoc(doc(db, "ESP32/Nano1/Logs/l1"), { moisture: 30 });
    await setDoc(doc(db, "ESP32/Nano1/Incidents/i1"), { type: "offline" });
    await setDoc(doc(db, "device_registry/FarmA"), {
      ownerUid: "alice",
      secret: "s3cret",
      members: {
        viewer: { control: false, settings: false },
        driver: { control: true, settings: false },
        manager: { control: true, settings: true },
      },
      ...access,
    });
  }
);

const as = (uid) => c.env().authenticatedContext(uid).firestore();
const viewer = () => as("viewer");
const driver = () => as("driver");
const manager = () => as("manager");
const outsider = () => as("outsider");

const SCHEDULE = {
  scheduleEnabled: true,
  scheduleMode: "allow",
  scheduleStart: "06:00",
  scheduleEnd: "18:00",
};

// ───────────── อ่าน ─────────────

test("สมาชิกทุกระดับอ่านอุปกรณ์ ฟาร์ม Log และ Incidents ของฟาร์มได้", async () => {
  for (const db of [viewer(), driver(), manager()]) {
    await assertSucceeds(getDoc(doc(db, "ESP32/Nano1")));
    await assertSucceeds(getDoc(doc(db, "device_registry/FarmA")));
    await assertSucceeds(getDoc(doc(db, "ESP32/Nano1/Logs/l1")));
    await assertSucceeds(getDoc(doc(db, "ESP32/Nano1/Incidents/i1")));
  }
});

test("คนนอกฟาร์มอ่านอะไรของฟาร์มไม่ได้", async () => {
  await assertFails(getDoc(doc(outsider(), "ESP32/Nano1")));
  await assertFails(getDoc(doc(outsider(), "device_registry/FarmA")));
  await assertFails(getDoc(doc(outsider(), "ESP32/Nano1/Logs/l1")));
  await assertFails(getDoc(doc(outsider(), "ESP32/Nano1/Incidents/i1")));
});

test("สมาชิกค้น 'อุปกรณ์ของฉัน' และ 'ฟาร์มของฉัน' ด้วย memberUids ได้ แต่ค้นของคนอื่นไม่ได้", async () => {
  await assertSucceeds(
    getDocs(
      query(collection(viewer(), "ESP32"), where("memberUids", "array-contains", "viewer"))
    )
  );
  await assertSucceeds(
    getDocs(
      query(
        collection(viewer(), "device_registry"),
        where("memberUids", "array-contains", "viewer")
      )
    )
  );
  await assertFails(
    getDocs(
      query(collection(viewer(), "ESP32"), where("memberUids", "array-contains", "alice"))
    )
  );
  await assertFails(
    getDocs(
      query(collection(outsider(), "ESP32"), where("memberUids", "array-contains", "viewer"))
    )
  );
});

test("เจ้าของยังค้นด้วย uid / ownerUid แบบเดิมได้ (ฟาร์มเก่าที่ยังไม่ซิงก์รายชื่อ)", async () => {
  await assertSucceeds(
    getDocs(query(collection(c.alice(), "ESP32"), where("uid", "==", "alice")))
  );
  await assertSucceeds(
    getDocs(
      query(collection(c.alice(), "device_registry"), where("ownerUid", "==", "alice"))
    )
  );
});

// ───────────── เขียนอุปกรณ์ ─────────────

test("ดูอย่างเดียว: เขียนอะไรบนอุปกรณ์ไม่ได้เลย", async () => {
  for (const patch of [
    { Valve: true },
    { Auto: false },
    { Automois: 40 },
    { desiredAuto: true },
    SCHEDULE,
  ]) {
    await assertFails(updateDoc(doc(viewer(), "ESP32/Nano1"), patch));
  }
});

test("ควบคุมได้: สั่ง Valve/Auto/Automois/desiredAuto ได้ (รวมเขียนพร้อมกัน) แต่ตั้งตารางเวลาไม่ได้", async () => {
  await assertSucceeds(updateDoc(doc(driver(), "ESP32/Nano1"), { Valve: true }));
  await assertSucceeds(
    updateDoc(doc(driver(), "ESP32/Nano1"), { desiredAuto: true, Auto: true, Valve: false })
  );
  await assertSucceeds(updateDoc(doc(driver(), "ESP32/Nano1"), { Automois: 35 }));
  await assertFails(updateDoc(doc(driver(), "ESP32/Nano1"), SCHEDULE));
  // เขียนปนกัน (แบบที่หน้าตั้งเวลาในแอปทำ) ต้องมีทั้งสองสิทธิ์
  await assertFails(
    updateDoc(doc(driver(), "ESP32/Nano1"), { ...SCHEDULE, Auto: true, Valve: false })
  );
});

test("จัดการได้: ตั้งตารางเวลา และบันทึกแบบปนกับ Auto/Valve ได้", async () => {
  await assertSucceeds(updateDoc(doc(manager(), "ESP32/Nano1"), SCHEDULE));
  await assertSucceeds(
    updateDoc(doc(manager(), "ESP32/Nano1"), {
      scheduleOverride: true,
      desiredAuto: true,
      Auto: true,
      Valve: false,
      scheduleExceptEnabled: false,
    })
  );
});

test("เจ้าของยังทำได้ทุกอย่างแบบเดิม แม้เอกสารไม่มีรายชื่อสิทธิ์", async () => {
  await assertSucceeds(
    updateDoc(doc(c.alice(), "ESP32/Nano1"), { ...SCHEDULE, Auto: false, Valve: true })
  );
  await c.env().withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "ESP32/Legacy"), { uid: "alice", groupId: "FarmA" });
  });
  await assertSucceeds(updateDoc(doc(c.alice(), "ESP32/Legacy"), { Valve: true }));
  await assertSucceeds(updateDoc(doc(c.alice(), "ESP32/Legacy"), SCHEDULE));
});

test("ไม่มีสมาชิกคนไหน (แม้ระดับจัดการ) แก้ค่าของบอร์ด รายชื่อสิทธิ์ หรือ uid บนอุปกรณ์ได้", async () => {
  for (const db of [driver(), manager(), c.alice()]) {
    for (const patch of [
      { Moisture: 99 },
      { uid: "manager" },
      { memberUids: ["alice", "manager", "evil"] },
      { controlUids: ["evil"] },
      { settingsUids: ["evil"] },
      { groupId: "FarmZ" },
    ]) {
      await assertFails(updateDoc(doc(db, "ESP32/Nano1"), patch));
    }
  }
});

test("คนนอกฟาร์มเขียนอุปกรณ์ของฟาร์มไม่ได้", async () => {
  await assertFails(updateDoc(doc(outsider(), "ESP32/Nano1"), { Valve: true }));
  await assertFails(updateDoc(doc(outsider(), "ESP32/Nano1"), SCHEDULE));
});

// ───────────── เขียนฟาร์ม ─────────────

test("ตั้งค่าฟาร์ม (ตารางเวลา/ข้ามฝน/ตำแหน่ง): เจ้าของและระดับจัดการได้ ระดับอื่นไม่ได้", async () => {
  const farmSettings = {
    scheduleEnabled: true,
    rainSkipEnabled: true,
    farmLat: 13.7,
    farmLon: 100.5,
  };
  await assertSucceeds(updateDoc(doc(c.alice(), "device_registry/FarmA"), farmSettings));
  await assertSucceeds(updateDoc(doc(manager(), "device_registry/FarmA"), farmSettings));
  await assertFails(updateDoc(doc(driver(), "device_registry/FarmA"), farmSettings));
  await assertFails(updateDoc(doc(viewer(), "device_registry/FarmA"), farmSettings));
  await assertFails(updateDoc(doc(outsider(), "device_registry/FarmA"), farmSettings));
});

test("ไม่มีใคร (client) แก้ ownerUid / สมาชิก / รายชื่อสิทธิ์ ของฟาร์มได้ — ต้องผ่าน backend", async () => {
  for (const db of [c.alice(), manager(), driver(), viewer()]) {
    for (const patch of [
      { ownerUid: "manager" },
      { members: { evil: { control: true, settings: true } } },
      { memberUids: ["evil"] },
      { controlUids: ["evil"] },
      { settingsUids: ["evil"] },
      { secret: "new" },
    ]) {
      await assertFails(updateDoc(doc(db, "device_registry/FarmA"), patch));
    }
  }
});

test("client สร้าง/ลบฟาร์มและเขียนคอลเลกชันคำเชิญเองไม่ได้", async () => {
  await assertFails(setDoc(doc(c.alice(), "device_registry/FarmNew"), { ownerUid: "alice" }));
  await assertFails(setDoc(doc(c.alice(), "farm_invites/ABCD2345"), { farmId: "FarmA" }));
  await assertFails(getDoc(doc(c.alice(), "farm_invites/ABCD2345")));
});

// ───────────── บอร์ดต้องไม่กระทบ ─────────────

test("บอร์ด: ยังอ่าน/เขียนอุปกรณ์ที่มีรายชื่อสมาชิกได้เหมือนเดิม", async () => {
  await assertSucceeds(getDoc(doc(c.esp(), "ESP32/Nano1")));
  await assertSucceeds(
    updateDoc(doc(c.esp(), "ESP32/Nano1"), {
      Moisture: 55,
      Time: "11:00",
      Error: "Sensor Read Error",
      ErrorTime: new Date(),
    })
  );
  await assertSucceeds(setDoc(doc(c.esp(), "ESP32/Nano1/Logs/l9"), { moisture: 1 }));
  await assertFails(updateDoc(doc(c.esp(), "ESP32/Nano1"), { Valve: true }));
});

// ───────────── กลุ่มอุปกรณ์ของฟาร์ม (device_registry.deviceGroups) ─────────────

test("กลุ่มอุปกรณ์ของฟาร์ม: ทุกคนในฟาร์มอ่านได้ แต่แก้ได้เฉพาะเจ้าของและระดับจัดการได้", async () => {
  const groups = [{ id: "g1", name: "ผักกาด", iconKey: "leaf", colorIndex: 0, deviceIds: ["Nano1"] }];
  await assertSucceeds(updateDoc(doc(c.alice(), "device_registry/FarmA"), { deviceGroups: groups }));
  await assertSucceeds(updateDoc(doc(manager(), "device_registry/FarmA"), { deviceGroups: groups }));
  await assertFails(updateDoc(doc(driver(), "device_registry/FarmA"), { deviceGroups: groups }));
  await assertFails(updateDoc(doc(viewer(), "device_registry/FarmA"), { deviceGroups: groups }));
  await assertFails(updateDoc(doc(outsider(), "device_registry/FarmA"), { deviceGroups: groups }));

  // สมาชิกทุกระดับเห็นกลุ่มที่เจ้าของตั้งไว้
  for (const db of [viewer(), driver(), manager()]) {
    const snap = await assertSucceeds(getDoc(doc(db, "device_registry/FarmA")));
    if (snap.data().deviceGroups?.[0]?.name !== "ผักกาด") throw new Error("สมาชิกต้องเห็นกลุ่มของฟาร์ม");
  }
});

test("เขียนกลุ่มพร้อมฟิลด์ที่ไม่อนุญาต (เช่น members) ในคำสั่งเดียวไม่ได้", async () => {
  await assertFails(
    updateDoc(doc(manager(), "device_registry/FarmA"), {
      deviceGroups: [],
      members: { evil: { control: true, settings: true } },
    })
  );
  await assertFails(
    updateDoc(doc(manager(), "device_registry/FarmA"), { deviceGroups: [], memberUids: ["evil"] })
  );
});
