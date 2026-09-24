import 'dart:html' as html;

void clearUrlQueryParams() {
  html.window.history.replaceState(null, '', '/');
}

void reloadPage() {
  html.window.location.reload();
}

// ขอตำแหน่งปัจจุบันจากเบราว์เซอร์ (browser geolocation) — คืน null ถ้าผู้ใช้
// ปฏิเสธสิทธิ์ หรือเบราว์เซอร์/อุปกรณ์ไม่รองรับ ไม่โยน exception ออกไปให้ผู้
// เรียกต้องจัดการเอง
Future<Map<String, double>?> getCurrentPosition() async {
  try {
    final position =
        await html.window.navigator.geolocation.getCurrentPosition();
    final lat = position.coords?.latitude;
    final lon = position.coords?.longitude;
    if (lat == null || lon == null) return null;
    return {'lat': lat.toDouble(), 'lon': lon.toDouble()};
  } catch (_) {
    return null;
  }
}
