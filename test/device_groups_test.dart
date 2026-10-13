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

  group("กลุ่มของฟาร์ม", () {
    test(
        "parseDeviceGroups ใส่ farmId จากเอกสารที่อ่าน ไม่ได้เก็บซ้ำในตัวกลุ่ม",
        () {
      final parsed = parseDeviceGroups({
        "deviceGroups": [a.toMap()],
      }, farmId: "FarmA");
      expect(parsed.single.farmId, "FarmA");
      expect(a.toMap().containsKey("farmId"), isFalse);
      expect(
          parseDeviceGroups({
            "deviceGroups": [a.toMap()]
          }).single.farmId,
          isNull);
    });

    test(
        "copyWith/setGroupMembers ไม่ทำ farmId หาย และ groupsOfFarm กรองตามฟาร์ม",
        () {
      final g1 = DeviceGroup(
          id: "1", name: "x", deviceIds: const ["n1"], farmId: "FarmA");
      final g2 = DeviceGroup(
          id: "2", name: "y", deviceIds: const ["n9"], farmId: "FarmB");
      final r = setGroupMembers([g1, g2], "1", ["n1", "n2"]);
      expect(r.map((g) => g.farmId), ["FarmA", "FarmB"]);
      expect(groupsOfFarm(r, "FarmB").map((g) => g.id), ["2"]);
      expect(groupsOfFarm(r, "none"), isEmpty);
    });

    test("ชื่อกลุ่มซ้ำได้ข้ามฟาร์ม ซ้ำในฟาร์มเดียวกันไม่ได้", () {
      final inA = [DeviceGroup(id: "1", name: "ผัก", farmId: "FarmA")];
      expect(validateGroupName("ผัก", inA), isNotNull);
      expect(validateGroupName("ผัก", groupsOfFarm(inA, "FarmB")), isNull);
    });

    test("สิทธิ์แก้กลุ่ม: เจ้าของและระดับจัดการได้ของฟาร์มนั้นเท่านั้น", () {
      final devices = [
        {
          "uid": "alice",
          "groupId": "FarmA",
          "settingsUids": ["alice", "mgr"],
          "controlUids": ["alice", "mgr", "drv"],
          "memberUids": ["alice", "mgr", "drv", "view"]
        },
        {
          "uid": "zed",
          "groupId": "FarmB",
          "settingsUids": ["zed"],
          "memberUids": ["zed", "mgr"]
        },
      ];
      expect(editableFarmsFrom(devices, "alice"), {"FarmA"});
      expect(editableFarmsFrom(devices, "mgr"),
          {"FarmA"}); // FarmB: mgr เป็นแค่สมาชิก
      expect(editableFarmsFrom(devices, "drv"), isEmpty);
      expect(editableFarmsFrom(devices, "view"), isEmpty);
      expect(editableFarmsFrom(devices, null), isEmpty);
      expect(
          editableFarmsFrom([
            {"uid": "alice"}
          ], "alice"),
          isEmpty); // ไม่มี groupId
    });

    test("farmOfDevicesFrom ข้ามอุปกรณ์ที่ไม่มี groupId", () {
      expect(
        farmOfDevicesFrom([
          ("n1", {"groupId": "FarmA"}),
          ("n2", {}),
          ("n3", {"groupId": 5})
        ]),
        {"n1": "FarmA"},
      );
    });
  });

  group("ย้ายกลุ่มเก่าของแต่ละคนขึ้นฟาร์ม", () {
    final farmOf = {"n1": "FarmA", "n2": "FarmA", "n3": "FarmB"};

    LegacyMigrationPlan plan(List<DeviceGroup> legacy,
            {Set<String> editable = const {"FarmA", "FarmB"},
            Map<String, List<DeviceGroup>> existing = const {}}) =>
        planLegacyMigration(
          legacy: legacy,
          farmOfDevice: farmOf,
          existingByFarm: existing,
          editableFarms: editable,
        );

    test("กลุ่มในฟาร์มเดียว → ไปอยู่ฟาร์มนั้น คงชื่อ/ไอคอน/สี และ id คงที่",
        () {
      final r = plan([
        DeviceGroup(
            id: "g1",
            name: "ผักกาด",
            deviceIds: ["n1", "n2"],
            iconKey: "herb",
            colorIndex: 3),
      ]);
      final moved = r.additions["FarmA"]!.single;
      expect(moved.id, migratedGroupId("g1", "FarmA"));
      expect(moved.name, "ผักกาด");
      expect(moved.deviceIds, ["n1", "n2"]);
      expect(moved.iconKey, "herb");
      expect(moved.colorIndex, 3);
      expect(moved.farmId, "FarmA");
      expect(r.migratedLegacyIds, {"g1"});
    });

    test("กลุ่มที่มีอุปกรณ์ต่างฟาร์ม → แตกเป็นกลุ่มชื่อเดียวกันฟาร์มละกลุ่ม",
        () {
      final r = plan([
        DeviceGroup(id: "g1", name: "ผัก", deviceIds: ["n1", "n3"])
      ]);
      expect(r.additions["FarmA"]!.single.deviceIds, ["n1"]);
      expect(r.additions["FarmB"]!.single.deviceIds, ["n3"]);
      expect(r.migratedLegacyIds, {"g1"});
    });

    test("ฟาร์มใดฟาร์มหนึ่งแก้ไม่ได้ → รอไว้ทั้งกลุ่ม ไม่ย้ายครึ่งๆ กลางๆ", () {
      final r = plan([
        DeviceGroup(id: "g1", name: "ผัก", deviceIds: ["n1", "n3"])
      ], editable: {
        "FarmA"
      });
      expect(r.additions, isEmpty);
      expect(r.migratedLegacyIds, isEmpty);
    });

    test(
        "ชื่อซ้ำกับกลุ่มในฟาร์ม → ต่อท้ายเลข อุปกรณ์ที่อยู่กลุ่มอื่นแล้วไม่ถูกดึงซ้ำ",
        () {
      final existing = {
        "FarmA": [
          DeviceGroup(
              id: "x", name: "ผักกาด", deviceIds: ["n2"], farmId: "FarmA")
        ],
      };
      final r = plan([
        DeviceGroup(id: "g1", name: "ผักกาด", deviceIds: ["n1", "n2"])
      ], existing: existing);
      final moved = r.additions["FarmA"]!.single;
      expect(moved.name, "ผักกาด 2");
      expect(moved.deviceIds, ["n1"]); // n2 อยู่กลุ่มเดิมของฟาร์มแล้ว
    });

    test("ย้ายซ้ำไม่ได้กลุ่มซ้ำ (id คงที่) แต่ยังนับว่าจัดการแล้ว", () {
      final already = {
        "FarmA": [
          DeviceGroup(
              id: migratedGroupId("g1", "FarmA"), name: "ผัก", farmId: "FarmA")
        ],
      };
      final r = plan([
        DeviceGroup(id: "g1", name: "ผัก", deviceIds: ["n1"])
      ], existing: already);
      expect(r.additions, isEmpty);
      expect(r.migratedLegacyIds, {"g1"});
    });

    test(
        "กลุ่มว่าง: มีฟาร์มเดียวที่แก้ได้ → ย้ายเข้าฟาร์มนั้น; หลายฟาร์ม → ทิ้ง; ไม่มีสิทธิ์ → รอ",
        () {
      final empty = [DeviceGroup(id: "g1", name: "ว่าง")];
      expect(
          plan(empty, editable: {"FarmA"}).additions["FarmA"]!.single.deviceIds,
          isEmpty);
      final multi = plan(empty);
      expect(multi.additions, isEmpty);
      expect(multi.migratedLegacyIds, {"g1"});
      final none = plan(empty, editable: {});
      expect(none.migratedLegacyIds, isEmpty);
    });

    test(
        "อุปกรณ์ที่ถูกลบไปแล้วไม่ถูกย้าย; กลุ่มที่เหลือแต่อุปกรณ์ที่หายไปไม่ทำให้พัง",
        () {
      final r = plan([
        DeviceGroup(id: "g1", name: "ผัก", deviceIds: ["gone", "n1"])
      ]);
      expect(r.additions["FarmA"]!.single.deviceIds, ["n1"]);
    });

    test(
        "uniqueGroupName ไม่ยาวเกิน ${maxGroupNameLength} และข้ามเลขที่ใช้แล้ว",
        () {
      final long = "ก" * maxGroupNameLength;
      final existing = [
        DeviceGroup(id: "1", name: long),
        DeviceGroup(id: "2", name: "${"ก" * (maxGroupNameLength - 2)} 2")
      ];
      final u = uniqueGroupName(long, existing);
      expect(u.length, lessThanOrEqualTo(maxGroupNameLength));
      expect(existing.any((g) => g.name.toLowerCase() == u.toLowerCase()),
          isFalse);
      expect(uniqueGroupName("ใหม่", existing), "ใหม่");
    });
  });
}
