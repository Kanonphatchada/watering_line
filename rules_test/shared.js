// ตัวช่วยกลางสำหรับชุดทดสอบ firestore.rules (รันบน emulator เท่านั้น)
// - useRules(): ตั้ง emulator ด้วยไฟล์กฎที่เลือก + ข้อมูลตั้งต้นก่อนทุกเทสต์
// - commonTests(): พฤติกรรมที่ "ต้องเหมือนเดิม" ทั้งก่อนและหลังแก้กฎ โดยเฉพาะ
//   ฝั่งบอร์ด ESP32 (ของเพื่อน) ที่ห้ามพัง — ใช้รันกับทั้งกฎเดิมและกฎใหม่
import test, { before, after, beforeEach } from "node:test";
import { readFileSync } from "node:fs";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  collection,
  query,
  where,
  getDocs,
  setLogLevel,
} from "firebase/firestore";

export {
  assertSucceeds,
  assertFails,
  test,
  doc,
  getDoc,
  setDoc,
  updateDoc,
  collection,
  query,
  where,
  getDocs,
};

setLogLevel("error");

// seedExtra(db): ข้อมูลตั้งต้นเพิ่มเติมของชุดทดสอบนั้นๆ (รันหลังข้อมูลตั้งต้นกลาง)
export function useRules(rulesUrl, projectId, seedExtra) {
  const state = { env: null };

  before(async () => {
    state.env = await initializeTestEnvironment({
      projectId,
      firestore: {
        rules: readFileSync(rulesUrl, "utf8"),
        host: "127.0.0.1",
        port: 8089,
      },
    });
  });

  after(async () => {
    await state.env.cleanup();
  });

  beforeEach(async () => {
    await state.env.clearFirestore();
    await state.env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "ESP32/Nano1"), {
        uid: "alice",
        groupId: "FarmA",
        Moisture: 30,
        Automois: 20,
        Valve: false,
        Auto: true,
        Time: "10:00",
      });
      await setDoc(doc(db, "ESP32/Nano2"), {
        uid: "bob",
        groupId: "FarmB",
        Moisture: 40,
        Automois: 20,
        Valve: false,
        Auto: false,
      });
      // อุปกรณ์ที่เพิ่งสร้างด้วยบอร์ด ยังไม่มีฟิลด์ uid เลย (เคสที่เคยทำให้กฎพัง)
      await setDoc(doc(db, "ESP32/NanoNew"), { groupId: "FarmFree" });
      await setDoc(doc(db, "ESP32/Nano1/Logs/l1"), { moisture: 30 });
      await setDoc(doc(db, "ESP32/Nano1/Incidents/i1"), { type: "offline" });
      await setDoc(doc(db, "device_registry/FarmA"), {
        ownerUid: "alice",
        secret: "s3cret",
      });
      await setDoc(doc(db, "device_registry/FarmB"), {
        ownerUid: "bob",
        secret: "b-secret",
      });
      await setDoc(doc(db, "device_registry/FarmFree"), {
        ownerUid: null,
        secret: "free-secret",
      });
      await setDoc(doc(db, "users/alice"), { displayName: "Alice" });
      if (seedExtra) await seedExtra(db);
    });
  });

  const get = () => state.env;
  return {
    env: get,
    esp: () =>
      get()
        .authenticatedContext("esp-uid", { email: "project@gg.com" })
        .firestore(),
    alice: () => get().authenticatedContext("alice").firestore(),
    bob: () => get().authenticatedContext("bob").firestore(),
    anon: () => get().unauthenticatedContext().firestore(),
  };
}

export function commonTests({ esp, alice, bob, anon }) {
  // ───────────── ฝั่งบอร์ด (project@gg.com) — ห้ามพังเด็ดขาด ─────────────

  test("บอร์ด: อ่านเอกสารอุปกรณ์ที่มี uid ได้", async () => {
    await assertSucceeds(getDoc(doc(esp(), "ESP32/Nano1")));
  });

  test("บอร์ด: อ่านเอกสารที่ไม่มีฟิลด์ uid ได้ (เคสที่เคยทำให้กฎพัง)", async () => {
    await assertSucceeds(getDoc(doc(esp(), "ESP32/NanoNew")));
  });

  test("บอร์ด: อ่านทั้งคอลเลกชันอุปกรณ์ได้ (รวมตัวที่ไม่มี uid)", async () => {
    await assertSucceeds(getDocs(collection(esp(), "ESP32")));
  });

  test("บอร์ด: เขียน Moisture/Time/Error/ErrorTime/lastSeen ได้", async () => {
    await assertSucceeds(
      updateDoc(doc(esp(), "ESP32/Nano1"), {
        Moisture: 55,
        Time: "11:00",
        Error: "Sensor Read Error",
        ErrorTime: new Date(),
        lastSeen: new Date(),
      })
    );
  });

  test("บอร์ด: เขียนลงเอกสารที่ไม่มี uid ได้", async () => {
    await assertSucceeds(
      updateDoc(doc(esp(), "ESP32/NanoNew"), { Moisture: 12, Time: "09:00" })
    );
  });

  test("บอร์ด: สร้างอุปกรณ์ใหม่ได้", async () => {
    await assertSucceeds(
      setDoc(doc(esp(), "ESP32/Brand"), { groupId: "FarmZ", Moisture: 0 })
    );
  });

  test("บอร์ด: สร้าง Log และอ่าน Log ได้", async () => {
    await assertSucceeds(
      setDoc(doc(esp(), "ESP32/Nano1/Logs/l2"), { moisture: 31 })
    );
    await assertSucceeds(getDoc(doc(esp(), "ESP32/Nano1/Logs/l1")));
  });

  test("บอร์ด: เขียน Valve/Auto/Automois/uid ไม่ได้ (คำสั่งเป็นของแอป/backend)", async () => {
    for (const patch of [
      { Valve: true },
      { Auto: false },
      { Automois: 99 },
      { uid: "esp-uid" },
    ]) {
      await assertFails(updateDoc(doc(esp(), "ESP32/Nano1"), patch));
    }
  });

  // ───────────── เจ้าของอุปกรณ์ ─────────────

  test("เจ้าของ: อ่านอุปกรณ์ตัวเองและค้นหาด้วย uid ได้", async () => {
    await assertSucceeds(getDoc(doc(alice(), "ESP32/Nano1")));
    await assertSucceeds(
      getDocs(query(collection(alice(), "ESP32"), where("uid", "==", "alice")))
    );
  });

  test("เจ้าของ: ควบคุม Auto/Valve/Automois และตั้งตารางเวลาได้", async () => {
    await assertSucceeds(
      updateDoc(doc(alice(), "ESP32/Nano1"), {
        Auto: false,
        Valve: true,
        Automois: 25,
      })
    );
    await assertSucceeds(
      updateDoc(doc(alice(), "ESP32/Nano1"), {
        scheduleEnabled: true,
        scheduleMode: "allow",
        scheduleStart: "06:00",
        scheduleEnd: "18:00",
        desiredAuto: true,
        scheduleOverride: { a: 1 },
      })
    );
  });

  test("เจ้าของ: เขียนค่าที่เป็นของบอร์ด (Moisture) ไม่ได้ และแก้ของคนอื่นไม่ได้", async () => {
    await assertFails(updateDoc(doc(alice(), "ESP32/Nano1"), { Moisture: 99 }));
    await assertFails(updateDoc(doc(alice(), "ESP32/Nano2"), { Valve: true }));
  });

  test("เจ้าของ: ดูประวัติ Incidents/Logs ของตัวเองได้ แต่เขียน Incidents ไม่ได้", async () => {
    await assertSucceeds(getDoc(doc(alice(), "ESP32/Nano1/Incidents/i1")));
    await assertSucceeds(getDoc(doc(alice(), "ESP32/Nano1/Logs/l1")));
    await assertFails(
      setDoc(doc(alice(), "ESP32/Nano1/Incidents/i2"), { type: "x" })
    );
  });

  test("เจ้าของฟาร์ม: ตั้งตารางเวลา/ข้ามฝนที่ device_registry ได้ แต่เปลี่ยนเจ้าของไม่ได้", async () => {
    await assertSucceeds(
      updateDoc(doc(alice(), "device_registry/FarmA"), {
        scheduleEnabled: true,
        rainSkipEnabled: true,
        farmLat: 13.7,
        farmLon: 100.5,
      })
    );
    await assertFails(
      updateDoc(doc(alice(), "device_registry/FarmA"), { ownerUid: "alice2" })
    );
  });

  test("เจ้าของฟาร์ม: อ่านเอกสารฟาร์มตัวเองได้", async () => {
    await assertSucceeds(getDoc(doc(alice(), "device_registry/FarmA")));
  });

  test("ผู้ใช้: อ่าน/เขียนเอกสาร users ของตัวเองได้ (กลุ่มอุปกรณ์เก็บที่นี่) แต่ของคนอื่นไม่ได้", async () => {
    await assertSucceeds(
      setDoc(
        doc(alice(), "users/alice"),
        { deviceGroups: [{ id: "g1", name: "ผักกาด", deviceIds: ["Nano1"] }] },
        { merge: true }
      )
    );
    await assertFails(getDoc(doc(bob(), "users/alice")));
    await assertFails(setDoc(doc(bob(), "users/alice"), { x: 1 }));
  });

  test("ยังไม่ล็อกอิน: อ่าน/เขียนอะไรไม่ได้เลย", async () => {
    await assertFails(getDoc(doc(anon(), "ESP32/Nano1")));
    await assertFails(getDoc(doc(anon(), "device_registry/FarmA")));
    await assertFails(updateDoc(doc(anon(), "ESP32/Nano1"), { Valve: true }));
  });
}
