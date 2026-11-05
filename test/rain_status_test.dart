import 'package:flutter_test/flutter_test.dart';
import 'package:watering_app/features/devices/services/rain_skip.dart';
import 'package:watering_app/features/devices/utils/time_text.dart';

void main() {
  final now = DateTime(2026, 11, 5, 14, 30);

  group('isRainCheckStale', () {
    test('เช็คภายใน 1 ชม. = ยังใช้ได้', () {
      expect(isRainCheckStale(now.subtract(const Duration(minutes: 20)), now),
          isFalse);
      expect(isRainCheckStale(now.subtract(const Duration(hours: 1)), now),
          isFalse);
    });

    test('เกิน 1 ชม. = ข้อมูลเก่า (เช่น cron หยุดไป 16 วัน)', () {
      expect(
          isRainCheckStale(
              now.subtract(const Duration(hours: 1, minutes: 1)), now),
          isTrue);
      expect(
          isRainCheckStale(now.subtract(const Duration(minutes: 24020)), now),
          isTrue);
    });
  });

  group('ข้อความเวลา', () {
    test('ระยะเวลาเป็นนาที/ชม./วัน แทนนาทีล้วน', () {
      expect(relativeTimeThai(now.subtract(const Duration(seconds: 30)), now),
          "เมื่อสักครู่");
      expect(relativeTimeThai(now.subtract(const Duration(minutes: 5)), now),
          "5 นาทีก่อน");
      expect(relativeTimeThai(now.subtract(const Duration(hours: 3)), now),
          "3 ชม.ก่อน");
      expect(
          relativeTimeThai(now.subtract(const Duration(minutes: 24020)), now),
          "16 วันก่อน");
    });

    test('เวลาจริง: วันนี้โชว์แค่เวลา วันอื่นเติมวันที่', () {
      expect(clockTimeThai(DateTime(2026, 11, 5, 9, 5), now), "09:05 น.");
      expect(clockTimeThai(DateTime(2026, 10, 19, 14, 10), now),
          "19 ต.ค. 14:10 น.");
    });
  });
}
