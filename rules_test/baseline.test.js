// "ภาพถ่าย" พฤติกรรมของกฎชุดเดิมที่ใช้งานจริงอยู่บน Console (baseline.rules) —
// รันบน emulator เท่านั้น ไว้เทียบกับกฎใหม่ (hardened.test.js): ทุกอย่างฝั่งบอร์ด
// และเจ้าของที่ผ่านที่นี่ต้องผ่านเหมือนกันกับกฎใหม่ ส่วนเทสต์ [HOLE] คือช่องโหว่
// ที่ชุดเดิม "ผ่าน" อยู่ (ไม่ควรผ่าน) และกฎใหม่ต้องปิดให้ล้มทุกข้อ
import {
  useRules,
  commonTests,
  test,
  assertSucceeds,
  doc,
  getDoc,
  updateDoc,
  collection,
  query,
  where,
  getDocs,
} from "./shared.js";

const c = useRules(
  new URL("./baseline.rules", import.meta.url),
  "demo-rules-baseline"
);
commonTests(c);

test("[HOLE] ผู้ใช้อื่นอ่านข้อมูลอุปกรณ์ของ alice ได้ (|| true)", async () => {
  await assertSucceeds(getDoc(doc(c.bob(), "ESP32/Nano1")));
});

test("[HOLE] ผู้ใช้อื่นอ่าน device_registry รวมรหัสลับ secret ได้", async () => {
  const snap = await assertSucceeds(
    getDoc(doc(c.bob(), "device_registry/FarmA"))
  );
  if (snap.data().secret !== "s3cret") {
    throw new Error("secret ควรอ่านได้ใน baseline");
  }
});

test("[HOLE] ผู้ใช้ใดๆ ตั้ง uid เป็นตัวเองบนอุปกรณ์ที่ยังไม่มีเจ้าของได้ โดยไม่ต้องใช้รหัส", async () => {
  await assertSucceeds(
    updateDoc(doc(c.bob(), "ESP32/NanoNew"), { uid: "bob" })
  );
});

test("[HOLE] ผู้ใช้ใดๆ ยึด device_registry ที่ยังไม่มีเจ้าของได้ โดยไม่ต้องใช้รหัส", async () => {
  await assertSucceeds(
    updateDoc(doc(c.bob(), "device_registry/FarmFree"), { ownerUid: "bob" })
  );
});

test("[HOLE] ผู้ใช้ค้นอุปกรณ์ด้วย groupId ทั้งที่ไม่ใช่เจ้าของได้", async () => {
  await assertSucceeds(
    getDocs(
      query(collection(c.bob(), "ESP32"), where("groupId", "==", "FarmA"))
    )
  );
});
