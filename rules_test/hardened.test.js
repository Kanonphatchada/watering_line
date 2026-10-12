// ทดสอบกฎใหม่ (../firestore.rules): พฤติกรรมฝั่งบอร์ดและเจ้าของต้องเหมือนเดิม
// ทุกข้อ (commonTests ชุดเดียวกับ baseline) และช่องโหว่ 5 ข้อต้องถูกปิด
import {
  useRules,
  commonTests,
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

const c = useRules(
  new URL("../firestore.rules", import.meta.url),
  "demo-rules-hardened"
);
commonTests(c);

// ───────────── ช่องโหว่ที่ต้องถูกปิด ─────────────

test("ผู้ใช้อื่นอ่านข้อมูลอุปกรณ์ของ alice ไม่ได้", async () => {
  await assertFails(getDoc(doc(c.bob(), "ESP32/Nano1")));
});

test("ผู้ใช้อื่นอ่าน device_registry (รหัสลับ) ของ alice ไม่ได้", async () => {
  await assertFails(getDoc(doc(c.bob(), "device_registry/FarmA")));
});

test("ผู้ใช้ตั้ง uid เองบนอุปกรณ์ที่ยังไม่มีเจ้าของไม่ได้ (ต้องผ่าน backend)", async () => {
  await assertFails(updateDoc(doc(c.bob(), "ESP32/NanoNew"), { uid: "bob" }));
});

test("ผู้ใช้ยึด device_registry ที่ว่างเองไม่ได้ (ต้องผ่าน backend)", async () => {
  await assertFails(
    updateDoc(doc(c.bob(), "device_registry/FarmFree"), { ownerUid: "bob" })
  );
});

test("ผู้ใช้ค้นอุปกรณ์ด้วย groupId ของคนอื่นไม่ได้", async () => {
  await assertFails(
    getDocs(
      query(collection(c.bob(), "ESP32"), where("groupId", "==", "FarmA"))
    )
  );
});

// ───────────── พฤติกรรมเพิ่มเติมของกฎใหม่ ─────────────

test("ฟาร์มที่ยังไม่มีเจ้าของ: ไม่มีใคร (client) อ่านได้ รวมถึงรหัสลับ", async () => {
  await assertFails(getDoc(doc(c.alice(), "device_registry/FarmFree")));
  await assertFails(getDoc(doc(c.esp(), "device_registry/FarmFree")));
});

test("ค้นฟาร์มของตัวเองด้วย ownerUid ได้ (หน้าแรกใช้) แต่ค้นแบบไม่กรองเจ้าของไม่ได้", async () => {
  await assertSucceeds(
    getDocs(
      query(
        collection(c.alice(), "device_registry"),
        where("ownerUid", "==", "alice")
      )
    )
  );
  await assertFails(getDocs(collection(c.alice(), "device_registry")));
});

test("ค้นฟาร์มด้วยรายชื่อ id: ผ่านถ้าทุกฟาร์มเป็นของตัวเอง แต่ล้มทั้งคำค้นถ้ามีฟาร์มคนอื่นปน", async () => {
  const { documentId } = await import("firebase/firestore");
  const byIds = (ids) =>
    getDocs(
      query(
        collection(c.alice(), "device_registry"),
        where(documentId(), "in", ids)
      )
    );
  await assertSucceeds(byIds(["FarmA"]));
  await assertFails(byIds(["FarmA", "FarmB"]));
});

test("client สร้าง/ลบ device_registry เองไม่ได้", async () => {
  await assertFails(setDoc(doc(c.alice(), "device_registry/New"), { a: 1 }));
  await assertFails(
    (await import("firebase/firestore")).deleteDoc(
      doc(c.alice(), "device_registry/FarmA")
    )
  );
});

test("ผู้ใช้อื่นอ่าน Logs/Incidents ของ alice ไม่ได้", async () => {
  await assertFails(getDoc(doc(c.bob(), "ESP32/Nano1/Logs/l1")));
  await assertFails(getDoc(doc(c.bob(), "ESP32/Nano1/Incidents/i1")));
});

test("อุปกรณ์ที่ไม่มี uid: ผู้ใช้ทั่วไปอ่านไม่ได้ แต่บอร์ดอ่านและเขียนได้", async () => {
  await assertFails(getDoc(doc(c.alice(), "ESP32/NanoNew")));
  await assertSucceeds(getDoc(doc(c.esp(), "ESP32/NanoNew")));
});
