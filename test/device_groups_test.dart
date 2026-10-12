import 'package:flutter_test/flutter_test.dart';
import 'package:watering_app/features/devices/services/device_groups.dart';

void main() {
  const a = DeviceGroup(id: 'a', name: 'ผักกาด', deviceIds: ['n1', 'n2']);
  const b = DeviceGroup(id: 'b', name: 'กวางตุ้ง', deviceIds: ['n3']);

  test('parse: ข้อมูลว่าง/ผิดรูปแบบไม่พัง ข้ามรายการเสีย', () {
    expect(parseDeviceGroups(null), isEmpty);
    expect(parseDeviceGroups({'deviceGroups': 'x'}), isEmpty);
    final parsed = parseDeviceGroups({
      'deviceGroups': [
        a.toMap(),
        {'id': 1, 'name': 'bad'},
        'junk',
        {'id': 'c', 'name': 'ไม่มีสมาชิก'},
      ],
    });
    expect(parsed.map((g) => g.id), ['a', 'c']);
    expect(parsed.last.deviceIds, isEmpty);
  });

  test('toMap/fromMap ย้อนกลับได้', () {
    final back = DeviceGroup.fromMap(a.toMap())!;
    expect(back.name, a.name);
    expect(back.deviceIds, a.deviceIds);
  });

  test('ชื่อกลุ่ม: ว่าง/ยาวเกิน/ซ้ำ ถูกปฏิเสธ แต่แก้ชื่อตัวเองได้', () {
    expect(validateGroupName('  ', [a, b]), isNotNull);
    expect(validateGroupName('x' * 31, [a, b]), isNotNull);
    expect(validateGroupName(' ผักกาด ', [a, b]), isNotNull);
    expect(validateGroupName('ผักกาด', [a, b], exceptId: 'a'), isNull);
    expect(validateGroupName('คะน้า', [a, b]), isNull);
  });

  test('ชื่อซ้ำไม่สนตัวพิมพ์เล็ก/ใหญ่', () {
    const g = DeviceGroup(id: 'x', name: 'Basil');
    expect(validateGroupName('basil', [g]), isNotNull);
  });

  test('เลือกอุปกรณ์เข้ากลุ่ม: ย้ายออกจากกลุ่มเดิม อยู่ได้กลุ่มเดียว', () {
    final r = setGroupMembers([a, b], 'b', ['n2', 'n3']);
    expect(r.firstWhere((g) => g.id == 'a').deviceIds, ['n1']);
    expect(r.firstWhere((g) => g.id == 'b').deviceIds.toSet(), {'n2', 'n3'});
    expect(groupOfDevice(r, 'n2')!.id, 'b');
  });

  test('เอาอุปกรณ์ออกจากกลุ่ม → กลับไปไม่ได้จัดกลุ่ม', () {
    final r = setGroupMembers([a, b], 'a', ['n1']);
    expect(groupOfDevice(r, 'n2'), isNull);
  });

  test('ลบกลุ่ม: สมาชิกกลับไปไม่ได้จัดกลุ่ม กลุ่มอื่นไม่กระทบ', () {
    final r = removeGroup([a, b], 'a');
    expect(r.map((g) => g.id), ['b']);
    expect(groupOfDevice(r, 'n1'), isNull);
    expect(groupOfDevice(r, 'n3')!.id, 'b');
  });

  test('เปลี่ยนชื่อกลุ่มแล้ว trim และไม่แตะสมาชิก', () {
    final r = renameGroup([a, b], 'a', '  ผักสลัด ');
    expect(r.first.name, 'ผักสลัด');
    expect(r.first.deviceIds, a.deviceIds);
  });

  test('ไอคอน/สี: กลุ่มเก่าที่ไม่มีฟิลด์ใช้ค่าตั้งต้น และเก็บ-อ่านกลับได้', () {
    final old = DeviceGroup.fromMap({'id': 'o', 'name': 'เก่า'})!;
    expect(old.iconKey, defaultGroupIconKey);
    expect(old.colorIndex, 0);

    final styled = restyleGroup([a, b], 'b', iconKey: 'fruit', colorIndex: 4);
    final back = DeviceGroup.fromMap(styled.last.toMap())!;
    expect(back.iconKey, 'fruit');
    expect(back.colorIndex, 4);
    expect(styled.first.iconKey, defaultGroupIconKey); // กลุ่มอื่นไม่โดน
  });

  test('ย้ายสมาชิก/เปลี่ยนชื่อ ไม่ทำให้ไอคอนและสีหาย', () {
    final styled = restyleGroup([a, b], 'a', iconKey: 'herb', colorIndex: 3);
    final moved =
        setGroupMembers(renameGroup(styled, 'a', 'โหรพา'), 'a', ['n1']);
    expect(moved.first.iconKey, 'herb');
    expect(moved.first.colorIndex, 3);
  });

  group('computeGroupStats', () {
    test('กลุ่มว่าง → ไม่มีค่าเฉลี่ย ไม่ต้องดู', () {
      final s = computeGroupStats([]);
      expect(s.count, 0);
      expect(s.avgMoisture, isNull);
      expect(s.needsAttention, 0);
    });

    test('นับดินแห้ง/ออฟไลน์/ผิดปกติ และนับตัวที่ต้องดูครั้งเดียวต่อตัว', () {
      final s = computeGroupStats([
        {'Moisture': 10, 'Automois': 20}, // แห้ง
        {'Moisture': 40, 'Automois': 20}, // ปกติ
        {
          'Moisture': 5,
          'Automois': 20,
          'offline': true
        }, // แห้ง+ออฟไลน์ = 1 ตัว
        {'Moisture': 50, 'faultType': 'sensor_error'}, // ผิดปกติ
      ]);
      expect(s.count, 4);
      expect(s.avgMoisture, closeTo(26.25, 1e-9));
      expect(s.dryCount, 2);
      expect(s.offlineCount, 1);
      expect(s.faultCount, 1);
      expect(s.needsAttention, 3);
    });

    test('ออฟไลน์ที่มี faultType ค้างอยู่ ไม่นับ fault ซ้ำ', () {
      final s = computeGroupStats([
        {'Moisture': 30, 'Automois': 20, 'offline': true, 'faultType': 'x'},
      ]);
      expect(s.offlineCount, 1);
      expect(s.faultCount, 0);
      expect(s.needsAttention, 1);
    });

    test('ไม่มี Automois ใช้ค่าตั้งต้น 20 เหมือนหน้าหลัก', () {
      final s = computeGroupStats([
        {'Moisture': 19},
        {'Moisture': 20},
      ]);
      expect(s.dryCount, 1);
    });
  });

  test('ตัดอุปกรณ์ที่ไม่มีอยู่แล้วออกจากรายชื่อสมาชิก', () {
    final r = pruneMissingDevices([a, b], {'n1', 'n3'});
    expect(r.first.deviceIds, ['n1']);
    expect(r.last.deviceIds, ['n3']);
  });
}
