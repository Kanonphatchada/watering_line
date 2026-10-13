import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:watering_app/features/devices/services/farm_members.dart';
import 'package:watering_app/features/devices/services/my_devices.dart';

void main() {
  group('ระดับสิทธิ์', () {
    test('levelOf/flagsOf ย้อนกลับได้ และ settings บังคับให้มี control', () {
      for (final level in MemberLevel.values) {
        final f = flagsOf(level);
        expect(levelOf(control: f.control, settings: f.settings), level);
      }
      expect(flagsOf(MemberLevel.viewer), (control: false, settings: false));
      expect(flagsOf(MemberLevel.controller), (control: true, settings: false));
      expect(flagsOf(MemberLevel.manager), (control: true, settings: true));
      // ข้อมูลผิดรูป (settings โดยไม่มี control) นับเป็นระดับจัดการ
      expect(levelOf(control: false, settings: true), MemberLevel.manager);
    });

    test('ทุกระดับมีป้ายและคำอธิบายภาษาไทย', () {
      for (final level in MemberLevel.values) {
        expect(levelLabel(level), isNotEmpty);
        expect(levelDescription(level), isNotEmpty);
      }
    });
  });

  group('สิทธิ์บนอุปกรณ์ (ตรงกับกฎ Firestore)', () {
    final device = {
      'uid': 'alice',
      'memberUids': ['alice', 'viewer', 'driver', 'manager'],
      'controlUids': ['alice', 'driver', 'manager'],
      'settingsUids': ['alice', 'manager'],
    };

    test('เจ้าของได้ทุกสิทธิ์ แม้เอกสารไม่มีรายชื่อ (ฟาร์มเก่า)', () {
      expect(canControlDevice({'uid': 'alice'}, 'alice'), isTrue);
      expect(canSettingsDevice({'uid': 'alice'}, 'alice'), isTrue);
      expect(isDeviceOwner({'uid': 'alice'}, 'alice'), isTrue);
    });

    test('ดูอย่างเดียว / ควบคุม / จัดการ ได้ตามรายชื่อ', () {
      expect(canControlDevice(device, 'viewer'), isFalse);
      expect(canSettingsDevice(device, 'viewer'), isFalse);
      expect(canControlDevice(device, 'driver'), isTrue);
      expect(canSettingsDevice(device, 'driver'), isFalse);
      expect(canControlDevice(device, 'manager'), isTrue);
      expect(canSettingsDevice(device, 'manager'), isTrue);
      expect(isDeviceOwner(device, 'manager'), isFalse);
    });

    test('คนนอก / ยังไม่ล็อกอิน / รายชื่อผิดชนิด ไม่มีสิทธิ์และไม่พัง', () {
      expect(canControlDevice(device, 'stranger'), isFalse);
      expect(canControlDevice(device, null), isFalse);
      expect(
          canSettingsDevice({'uid': 'a', 'settingsUids': 'x'}, 'x'), isFalse);
      expect(canControlDevice({}, 'alice'), isFalse);
    });

    test('สิทธิ์ตั้งค่าระดับฟาร์ม: เจ้าของและ settingsUids', () {
      final farm = {
        'ownerUid': 'alice',
        'settingsUids': ['alice', 'manager'],
      };
      expect(canSettingsFarm(farm, 'alice'), isTrue);
      expect(canSettingsFarm(farm, 'manager'), isTrue);
      expect(canSettingsFarm(farm, 'driver'), isFalse);
      expect(canSettingsFarm(farm, null), isFalse);
    });
  });

  group('FarmMember.parseAll', () {
    test('ว่าง/ไม่ใช่ map → ไม่มีสมาชิก', () {
      expect(FarmMember.parseAll(null), isEmpty);
      expect(FarmMember.parseAll({'members': 'x'}), isEmpty);
      expect(FarmMember.parseAll({}), isEmpty);
    });

    test('อ่านชื่อ ระดับ วันที่เข้าร่วม เรียงเก่าสุดก่อน ข้ามรายการเสีย', () {
      final members = FarmMember.parseAll({
        'members': {
          'late': {
            'control': true,
            'settings': false,
            'name': 'Late',
            'joinedAt': 2000
          },
          'early': {
            'control': true,
            'settings': true,
            'name': 'Early',
            'joinedAt': 1000
          },
          'noName': {'control': false, 'joinedAt': 1500},
          'junk': 'not a map',
        },
      });
      expect(members.map((m) => m.uid), ['early', 'noName', 'late']);
      expect(members[0].level, MemberLevel.manager);
      expect(members[1].level, MemberLevel.viewer);
      expect(members[1].name, '');
      expect(members[2].level, MemberLevel.controller);
      expect(members[0].joinedAt!.millisecondsSinceEpoch, 1000);
    });
  });

  group('mergeLatestById', () {
    test('รอให้ทั้งสองสตรีมส่งค่าแรกก่อน แล้วรวมแบบไม่ซ้ำ เรียงตาม id',
        () async {
      final a = StreamController<List<String>>();
      final b = StreamController<List<String>>();
      final out = <List<String>>[];
      final sub =
          mergeLatestById<String>(a.stream, b.stream, (s) => s).listen(out.add);

      a.add(['n2', 'n1']);
      await Future<void>.delayed(Duration.zero);
      expect(out, isEmpty); // ยังรอสตรีม b

      b.add(['n3', 'n1']);
      await Future<void>.delayed(Duration.zero);
      expect(out.last, ['n1', 'n2', 'n3']);

      a.add(['n2']); // n1 หายจาก a แต่ยังอยู่ใน b
      await Future<void>.delayed(Duration.zero);
      expect(out.last, ['n1', 'n2', 'n3']);

      b.add([]);
      await Future<void>.delayed(Duration.zero);
      expect(out.last, ['n2']);

      await sub.cancel();
      await a.close();
      await b.close();
    });

    test('error จากสตรีมใดส่งต่อออกไป และยกเลิกฟังทั้งคู่เมื่อผู้ฟังยกเลิก',
        () async {
      var cancelledA = false;
      var cancelledB = false;
      final a =
          StreamController<List<String>>(onCancel: () => cancelledA = true);
      final b =
          StreamController<List<String>>(onCancel: () => cancelledB = true);
      final errors = <Object>[];
      final sub = mergeLatestById<String>(a.stream, b.stream, (s) => s)
          .listen((_) {}, onError: errors.add);

      a.addError('boom');
      await Future<void>.delayed(Duration.zero);
      expect(errors, ['boom']);

      await sub.cancel();
      expect(cancelledA, isTrue);
      expect(cancelledB, isTrue);
    });
  });
}
