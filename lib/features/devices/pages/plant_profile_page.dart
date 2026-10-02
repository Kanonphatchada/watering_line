import 'package:flutter/material.dart';
import '../../../shared/widgets/app_popup.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/fruit_profiles.dart';
import '../services/plant_profile.dart';
import '../widgets/fruit_icon.dart';

// หน้าตั้งชนิดพืช — เดิมเป็น dialog ที่รวมรายการพืช + รายการอุปกรณ์ไว้ใน
// ป็อปอัพเดียว ยาวและรกเกินไป แยกเป็นหน้าเต็มแบ่ง 2 ขั้น (เลือกพืช →
// เลือกอุปกรณ์) ฟาร์มเดียวปลูกได้หลายพืช เลยให้ติ๊กเฉพาะแปลงที่ต้องการ
// ตัวที่ไม่ได้ติ๊กคงค่าเดิมไว้ เขียนแค่ Automois จึงไม่ต้องแก้ Firestore rules
class PlantProfilePage extends StatefulWidget {
  final List<QueryDocumentSnapshot> docs;
  // เปิดจากปุ่ม "เปลี่ยน" บนการ์ด — ติ๊กอุปกรณ์ตัวนี้ไว้ให้ และเลือกฟาร์ม
  // ของมันให้เลย
  final String? initialDeviceId;

  const PlantProfilePage({
    super.key,
    required this.docs,
    this.initialDeviceId,
  });

  @override
  State<PlantProfilePage> createState() => _PlantProfilePageState();
}

class _PlantProfilePageState extends State<PlantProfilePage> {
  late final List<String> _groupIds = widget.docs
      .map((d) => (d.data() as Map<String, dynamic>)['groupId'] as String?)
      .whereType<String>()
      .toSet()
      .toList();
  late String? _groupId = widget.docs
          .where((d) => d.id == widget.initialDeviceId)
          .map((d) => (d.data() as Map<String, dynamic>)['groupId'] as String?)
          .firstOrNull ??
      _groupIds.firstOrNull;

  // 'custom' = กำหนดเอง, null = ยังไม่ได้เลือก
  String? _plantId;
  final _customController = TextEditingController();
  late final _checked = <String>{
    if (widget.initialDeviceId != null) widget.initialDeviceId!,
  };
  // ค่าที่เพิ่งบันทึก — หน้านี้ได้ docs มาเป็น snapshot ตอนเปิด เลยจำค่าใหม่
  // ไว้เองให้บรรทัด "ตอนนี้" อัปเดตทันทีโดยไม่ต้องปิดเปิดหน้าใหม่
  final _savedTargets = <String, double>{};
  bool _saving = false;

  // ไม้ผล: เลือกผลไม้ → เลือกช่วง → ค่า % ของช่วงนั้น (แก้เองได้)
  String? _fruitId;
  String? _stageId;
  final _fruitController = TextEditingController();
  final _daysController = TextEditingController();

  // ผลไม้/ช่วงที่เลือกไว้ของแต่ละอุปกรณ์ เก็บใน users/{uid}.plantSettings
  // (ESP32 doc เขียนได้แค่ฟิลด์ในลิสต์ของ rules เลยเก็บฝั่งผู้ใช้แทน ไม่ต้อง
  // แก้ rules และไม่กระทบบอร์ด — บอร์ดยังอ่านแค่ Automois เหมือนเดิม)
  final _uid = FirebaseAuth.instance.currentUser?.uid;
  Map<String, dynamic> _settings = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    if (_uid == null) return;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(_uid).get();
      final s = doc.data()?['plantSettings'];
      if (s is Map<String, dynamic> && mounted) setState(() => _settings = s);
    } catch (_) {
      // อ่านไม่ได้ก็แค่แสดงชื่อพืชจาก % แบบเดิม
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    _fruitController.dispose();
    _daysController.dispose();
    super.dispose();
  }

  FruitProfile? get _fruit => fruitById(_fruitId);

  FruitStage? get _stage =>
      _fruit?.stages.where((s) => s.id == _stageId).firstOrNull;

  String get _selectionLabel {
    if (_plantId == 'fruit') {
      return [_fruit?.label, _stage?.label].whereType<String>().join(' · ');
    }
    return _profile?.label ?? 'กำหนดเอง';
  }

  List<QueryDocumentSnapshot> get _groupDocs => widget.docs
      .where((d) => (d.data() as Map<String, dynamic>)['groupId'] == _groupId)
      .toList();

  double _targetOf(QueryDocumentSnapshot d) =>
      _savedTargets[d.id] ??
      ((d.data() as Map<String, dynamic>)['Automois'] ?? 20).toDouble();

  PlantProfile? get _profile =>
      plantProfiles.where((p) => p.id == _plantId).firstOrNull;

  double? get _newTarget {
    double? parse(TextEditingController c) {
      final v = double.tryParse(c.text.trim());
      return (v == null || v < 0 || v > 100) ? null : v;
    }

    if (_plantId == 'custom') return parse(_customController);
    if (_plantId == 'fruit') {
      return _stage == null ? null : parse(_fruitController);
    }
    return _profile?.targetMoisture;
  }

  Future<void> _save() async {
    final target = _newTarget;
    if (target == null || _checked.isEmpty) return;
    setState(() => _saving = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final d in _groupDocs.where((d) => _checked.contains(d.id))) {
        batch.update(d.reference, {'Automois': target});
      }
      await batch.commit();
    } catch (err) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorPopup(context, "บันทึกไม่สำเร็จ: $err");
      return;
    }

    // บันทึกว่าเลือกพืช/ผลไม้/ช่วงไหน แยกจาก Automois — ถ้าบันทึกส่วนนี้
    // ไม่สำเร็จ ค่าความชื้นก็เข้าบอร์ดไปแล้ว แค่ป้ายชื่อจะเดาจาก % แทน
    final stress = _plantId == 'fruit' && _stage?.stress == true;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    Map<String, dynamic> settingFor(String id) {
      // ช่วงงดน้ำ: เก็บวันที่เริ่มไว้นับวัน — ถ้าอุปกรณ์อยู่ช่วงเดิมอยู่แล้ว
      // (กดบันทึกซ้ำเพื่อแก้ % หรือจำนวนวัน) ใช้วันที่เริ่มเดิม ไม่นับใหม่
      final prev = _settings[id];
      final sameStage = prev is Map &&
          prev['fruit'] == _fruitId &&
          prev['stage'] == _stageId &&
          prev['since'] is num;
      return {
        'plant': _plantId,
        'target': target,
        if (_plantId == 'fruit') ...{'fruit': _fruitId, 'stage': _stageId},
        if (stress) ...{
          'since': sameStage ? prev['since'] : nowMs,
          'days': int.tryParse(_daysController.text.trim()) ??
              _stage?.maxDays ??
              14,
        },
      };
    }

    final newSettings = {for (final id in _checked) id: settingFor(id)};
    if (_uid != null) {
      try {
        // เขียนทั้งก้อนต่ออุปกรณ์ (แทนที่ของเดิม) เพื่อให้ since/days ของ
        // ช่วงก่อนหน้าหายไปด้วยเมื่อเปลี่ยนออกจากช่วงงดน้ำ
        await FirebaseFirestore.instance.collection('users').doc(_uid).update({
          for (final e in newSettings.entries)
            FieldPath(['plantSettings', e.key]): e.value,
        });
        _settings.addAll(newSettings);
      } on FirebaseException catch (e) {
        // ยังไม่มี users doc → update ใช้ไม่ได้ สร้างด้วย set แทน
        if (e.code == 'not-found') {
          try {
            await FirebaseFirestore.instance.collection('users').doc(_uid).set(
              {'plantSettings': newSettings},
              SetOptions(merge: true),
            );
            _settings.addAll(newSettings);
          } catch (_) {}
        }
      } catch (_) {}
    }

    if (!mounted) return;
    final count = _checked.length;
    setState(() {
      for (final id in _checked) {
        _savedTargets[id] = target;
      }
      _checked.clear();
      _saving = false;
    });
    showSuccessPopup(
        context,
        "ตั้ง $count อุปกรณ์เป็น $_selectionLabel "
        "(${formatMoisture(target)}%) แล้ว");
  }

  @override
  Widget build(BuildContext context) {
    final groupDocs = _groupDocs;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.local_florist_outlined),
            SizedBox(width: 8),
            Text("ชนิดพืช"),
          ],
        ),
      ),
      body: _groupId == null
          ? const Center(child: Text("ไม่พบกลุ่ม/ฟาร์มของอุปกรณ์เลย"))
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    if (_groupIds.length > 1) ...[
                      DropdownButtonFormField<String>(
                        initialValue: _groupId,
                        decoration: const InputDecoration(
                          labelText: "กลุ่ม/ฟาร์ม",
                          isDense: true,
                        ),
                        items: [
                          for (final g in _groupIds)
                            DropdownMenuItem(value: g, child: Text(g)),
                        ],
                        onChanged: (g) => setState(() {
                          _groupId = g;
                          _checked.clear();
                        }),
                      ),
                      const SizedBox(height: 20),
                    ],
                    const _StepTitle(number: 1, title: "เลือกชนิดพืช"),
                    _buildPlantGrid(),
                    const SizedBox(height: 28),
                    _StepTitle(
                      number: 2,
                      title: "เลือกอุปกรณ์",
                      trailing: TextButton(
                        onPressed: () => setState(() {
                          if (_checked.length == groupDocs.length) {
                            _checked.clear();
                          } else {
                            _checked.addAll(groupDocs.map((d) => d.id));
                          }
                        }),
                        child: Text(
                          _checked.length == groupDocs.length
                              ? "ไม่เลือกเลย"
                              : "เลือกทั้งหมด",
                        ),
                      ),
                    ),
                    Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final d in groupDocs) _buildDeviceRow(d),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: _groupId == null ? null : _buildSaveBar(),
    );
  }

  Widget _buildPlantGrid() {
    const spacing = 12.0;
    final selected = _profile;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 560 ? 3 : 2;
          final tileWidth =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final p in plantProfiles)
                SizedBox(
                  width: tileWidth,
                  child: _PlantTile(
                    icon: p.icon,
                    fruitIcon: p.id == 'fruit',
                    color: p.color,
                    label: p.label,
                    definition: p.definition,
                    value: p.id == 'fruit'
                        ? "ตามช่วง"
                        : "${formatMoisture(p.targetMoisture)}%",
                    selected: _plantId == p.id,
                    // กดการ์ดเดิมซ้ำ = ยกเลิกการเลือก
                    onTap: () => setState(
                      () => _plantId = _plantId == p.id ? null : p.id,
                    ),
                  ),
                ),
              SizedBox(
                width: tileWidth,
                child: _PlantTile(
                  icon: Icons.tune,
                  color: _customColor,
                  label: "กำหนดเอง",
                  definition:
                      "รู้ค่าความชื้นที่ต้องการอยู่แล้ว กรอกตัวเลขเองได้",
                  value: null,
                  selected: _plantId == 'custom',
                  onTap: () => setState(
                    () => _plantId = _plantId == 'custom' ? null : 'custom',
                  ),
                ),
              ),
            ],
          );
        }),
        // รายละเอียดเฉพาะพืชที่เลือก (คืออะไร + ตัวอย่าง + วิธีดูแล) ค่อยๆ
        // ขยายลงมา แทนการโชว์ทุกอันพร้อมกันจนรก
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _plantId == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    key: ValueKey(_plantId),
                    padding: const EdgeInsets.only(top: 14),
                    child: _plantId == 'fruit'
                        ? _buildFruitPanel(selected!.color)
                        : selected != null
                            ? _PlantDetail(profile: selected)
                            : _buildCustomInput(),
                  ),
          ),
        ),
      ],
    );
  }

  // แผงไม้ผล: เลือกผลไม้ → เลือกช่วงของต้นตอนนี้ → ค่าแนะนำเติมให้ในช่อง
  // แต่เกษตรกรแก้ตัวเลขเองได้เสมอ (ดินและพันธุ์แต่ละสวนไม่เหมือนกัน)
  Widget _buildFruitPanel(Color c) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    final fruit = _fruit;
    final stage = _stage;

    return _DetailShell(
      color: c,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "ปลูกผลไม้อะไร",
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in fruitProfiles)
                ChoiceChip(
                  label: Text(f.label),
                  selected: _fruitId == f.id,
                  showCheckmark: false,
                  selectedColor: c.withValues(alpha: 0.25),
                  side: BorderSide(
                    color: _fruitId == f.id ? c : c.withValues(alpha: 0.3),
                  ),
                  labelStyle: TextStyle(
                    fontWeight: _fruitId == f.id ? FontWeight.w700 : null,
                  ),
                  shape: const StadiumBorder(),
                  onSelected: (_) => setState(() {
                    _fruitId = _fruitId == f.id ? null : f.id;
                    _stageId = null;
                  }),
                ),
            ],
          ),
          if (fruit != null) ...[
            const SizedBox(height: 18),
            Text(
              "ตอนนี้${fruit.label}อยู่ช่วงไหน",
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final (i, s) in fruit.stages.indexed)
              _StageTile(
                number: i + 1,
                stage: s,
                color: c,
                selected: _stageId == s.id,
                onTap: () => setState(() {
                  // กดช่วงเดิมซ้ำ = ยกเลิก เหมือนการ์ดพืช
                  _stageId = _stageId == s.id ? null : s.id;
                  if (_stageId != null) {
                    _fruitController.text = formatMoisture(s.targetMoisture);
                    _daysController.text = "${s.maxDays ?? ''}";
                  }
                }),
              ),
          ],
          if (stage != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _fruitController,
                    onChanged: (_) => setState(() {}),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: "ความชื้นเป้าหมาย",
                      helperText: "ปรับเองได้ตามสวน",
                      suffixText: "%",
                      isDense: true,
                      errorText: _newTarget == null ? "กรอกตัวเลข 0-100" : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_newTarget != stage.targetMoisture)
                  TextButton.icon(
                    onPressed: () => setState(
                      () => _fruitController.text =
                          formatMoisture(stage.targetMoisture),
                    ),
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: Text(
                      "ค่าแนะนำ ${formatMoisture(stage.targetMoisture)}%",
                    ),
                  ),
              ],
            ),
            if (stage.stress)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _stressColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 20, color: _stressColor),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "ช่วงงดน้ำ · หน้าหลักจะนับวันให้",
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        SizedBox(
                          width: 150,
                          child: TextField(
                            controller: _daysController,
                            onChanged: (_) => setState(() {}),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: "งดน้ำประมาณ",
                              suffixText: "วัน",
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "แนะนำ ${stage.minDays}–${stage.maxDays} วัน",
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _MoreInfo(
                      label: "ช่วงนี้ทำงานยังไง",
                      color: _stressColor,
                      text: "ระบบจะรดน้ำเฉพาะตอนดินแห้งต่ำกว่า "
                          "${formatMoisture(_newTarget ?? stage.targetMoisture)}% "
                          "เพื่อให้ต้นเครียดแต่ไม่ตาย หน้าหลักจะนับวันและเตือน"
                          "เมื่อใกล้ครบ เห็นตาดอกแล้วให้เปลี่ยนเป็นช่วง \"ออกดอก\"",
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 8),
          _MoreInfo(
            label: "ค่าแนะนำมาจากไหน",
            color: c,
            text: "ค่าแนะนำเป็นจุดเริ่มต้นสำหรับดินร่วน ควรปรับตามดินและคำแนะนำ"
                "ของเกษตรในพื้นที่",
          ),
        ],
      ),
    );
  }

  Widget _buildCustomInput() {
    // ช่องกรอกเอง + เครื่องคำนวณอยู่ในแผงเดียวกัน — คนที่เลือก "กำหนดเอง"
    // คือคนที่ต้องหาตัวเลขเอง จึงวางตัวช่วยคำนวณไว้ตรงนี้เลย
    return _DetailShell(
      color: _customColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: TextField(
              controller: _customController,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: "ความชื้นเป้าหมาย",
                helperText: "รู้ค่าที่ต้องการอยู่แล้ว กรอกเองได้",
                suffixText: "%",
                isDense: true,
                errorText:
                    _customController.text.isNotEmpty && _newTarget == null
                        ? "กรอกตัวเลข 0-100"
                        : null,
              ),
            ),
          ),
          Divider(
            height: 32,
            color: _customColor.withValues(alpha: 0.25),
          ),
          _MoistureCalculator(
            color: _customColor,
            onUse: (v) => setState(
              () => _customController.text = formatMoisture(v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceRow(QueryDocumentSnapshot d) {
    final target = _targetOf(d);
    final setting = _settings[d.id];
    final label = plantLabelFor(
      target,
      setting is Map<String, dynamic> ? setting : null,
    );
    final muted = Theme.of(context).textTheme.bodySmall?.color;

    return CheckboxListTile(
      value: _checked.contains(d.id),
      onChanged: (v) => setState(
        () => v == true ? _checked.add(d.id) : _checked.remove(d.id),
      ),
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(d.id),
      secondary: Text(
        "$label · ${formatMoisture(target)}%",
        style: TextStyle(fontSize: 13, color: muted),
      ),
    );
  }

  Widget _buildSaveBar() {
    final target = _newTarget;
    final ready = target != null && _checked.isNotEmpty && !_saving;
    final String hint;
    if (_plantId == null) {
      hint = "เลือกชนิดพืชก่อน";
    } else if (_plantId == 'fruit' && _fruit == null) {
      hint = "เลือกชนิดผลไม้";
    } else if (_plantId == 'fruit' && _stage == null) {
      hint = "เลือกช่วงของต้น";
    } else if (_checked.isEmpty) {
      hint = "ติ๊กอุปกรณ์ที่ต้องการ";
    } else if (target == null) {
      hint = "กรอกความชื้นเป้าหมาย";
    } else {
      hint = "ตั้ง ${_checked.length} อุปกรณ์เป็น "
          "$_selectionLabel (${formatMoisture(target)}%)";
    }

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(hint, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: ready ? _save : null,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("บันทึก"),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepTitle extends StatelessWidget {
  final int number;
  final String title;
  final Widget? trailing;

  const _StepTitle({required this.number, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: scheme.primary,
            child: Text(
              "$number",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ค่าดินสำหรับเครื่องคำนวณ — % ความชื้นโดยปริมาตร (VWC) ตามที่เซนเซอร์วัด
// fieldCapacity = ดินอุ้มน้ำได้เต็มที่หลังน้ำส่วนเกินไหลออก,
// wiltingPoint = ต่ำกว่านี้พืชเริ่มเหี่ยวถาวร (ค่าทั่วไปจากตำราปฐพีวิทยา)
// dryTolerant = ค่าสำหรับพืชทนแล้งซึ่งปล่อยให้แห้งใกล้จุดเหี่ยวได้
class _Soil {
  final String label;
  final double fieldCapacity;
  final double wiltingPoint;
  final double dryTolerant;

  const _Soil(
      this.label, this.fieldCapacity, this.wiltingPoint, this.dryTolerant);
}

const _soils = [
  _Soil("ดินทราย", 12, 5, 4),
  _Soil("ดินร่วน", 30, 12, 10),
  _Soil("ดินเหนียว", 40, 22, 20),
];

// ความต้องการน้ำของพืช = สัดส่วนน้ำที่ยอมให้ดินแห้งไปก่อนรดรอบใหม่
// (null = พืชทนแล้ง ใช้ dryTolerant ของดินแทน) ค่าชุดเดียวกับที่ใช้คำนวณ
// preset ใน plant_profile.dart — ดินร่วนได้ 25/22/20/18/10 ตรงกันพอดี
const _waterNeeds = <(String, double?)>[
  ("ชอบชื้นมาก", 0.30),
  ("ชื้นปานกลาง", 0.45),
  ("ชื้นน้อย", 0.55),
  ("ค่อนข้างแห้ง", 0.65),
  ("ทนแล้ง", null),
];

class _MoistureCalculator extends StatefulWidget {
  final Color color;
  final ValueChanged<double> onUse;

  const _MoistureCalculator({required this.color, required this.onUse});

  @override
  State<_MoistureCalculator> createState() => _MoistureCalculatorState();
}

class _MoistureCalculatorState extends State<_MoistureCalculator> {
  int _soil = 1;
  int _need = 0;

  double get _result {
    final soil = _soils[_soil];
    final dry = _waterNeeds[_need].$2;
    if (dry == null) return soil.dryTolerant;
    return (soil.wiltingPoint +
            (soil.fieldCapacity - soil.wiltingPoint) * (1 - dry))
        .roundToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    final c = widget.color;
    final soil = _soils[_soil];
    final dry = _waterNeeds[_need].$2;

    Widget chips(List<String> labels, int selected, ValueChanged<int> onTap) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < labels.length; i++)
            ChoiceChip(
              label: Text(labels[i]),
              selected: selected == i,
              showCheckmark: false,
              selectedColor: c.withValues(alpha: 0.22),
              side: BorderSide(
                color: selected == i ? c : c.withValues(alpha: 0.25),
              ),
              labelStyle: TextStyle(
                fontWeight: selected == i ? FontWeight.w700 : null,
                color: selected == i ? c : null,
              ),
              shape: const StadiumBorder(),
              onSelected: (_) => setState(() => onTap(i)),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.calculate_outlined, size: 20, color: c),
            const SizedBox(width: 8),
            const Text(
              "ไม่แน่ใจ? คำนวณจากชนิดดินและพืช",
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text("ชนิดดิน", style: TextStyle(fontSize: 12, color: muted)),
        const SizedBox(height: 6),
        chips([for (final s in _soils) s.label], _soil, (i) => _soil = i),
        const SizedBox(height: 14),
        Text("พืชต้องการน้ำ", style: TextStyle(fontSize: 12, color: muted)),
        const SizedBox(height: 6),
        chips([for (final n in _waterNeeds) n.$1], _need, (i) => _need = i),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [c.withValues(alpha: 0.22), c.withValues(alpha: 0.06)],
            ),
          ),
          child: Row(
            children: [
              // ตัวเลขเปลี่ยนแบบเลื่อนขึ้นลงนุ่มๆ ทุกครั้งที่เลือกดิน/พืชใหม่
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.3),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: Text(
                  "${formatMoisture(_result)}%",
                  key: ValueKey(_result),
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: c,
                  ),
                ),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => widget.onUse(_result),
                child: const Text("ใช้ค่านี้"),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _MoreInfo(
          label: "ดูวิธีคำนวณ",
          color: c,
          text: dry == null
              ? "พืชทนแล้ง ปล่อยให้ดินแห้งใกล้จุดเหี่ยว "
                  "(${formatMoisture(soil.wiltingPoint)}%) ได้"
              : "สูตร: จุดเหี่ยว + (ความจุน้ำของดิน − จุดเหี่ยว) × "
                  "สัดส่วนน้ำที่ต้องเหลือ\n"
                  "= ${formatMoisture(soil.wiltingPoint)} + "
                  "(${formatMoisture(soil.fieldCapacity)} − "
                  "${formatMoisture(soil.wiltingPoint)}) × "
                  "${formatMoisture(((1 - dry) * 100).roundToDouble())}% "
                  "≈ ${formatMoisture(_result)}%",
        ),
      ],
    );
  }
}

const _customColor = Color(0xFF7E57C2);
const _stressColor = Color(0xFFE65100);

// ปุ่ม "ดูเพิ่ม ▾" — ซ่อนคำอธิบายยาวไว้ก่อน กดแล้วค่อยเลื่อนลงมา หน้าจอ
// จะได้เห็นแค่สิ่งที่ต้องเลือก ข้อความครบเหมือนเดิมแต่ไม่โชว์พร้อมกันจนรก
class _MoreInfo extends StatefulWidget {
  final String label;
  final String text;
  final Color color;

  const _MoreInfo({
    required this.label,
    required this.text,
    required this.color,
  });

  @override
  State<_MoreInfo> createState() => _MoreInfoState();
}

class _MoreInfoState extends State<_MoreInfo> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: 16, color: c),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: c,
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more, size: 18, color: c),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(22, 2, 0, 4),
                  child: Text(
                    widget.text,
                    style: const TextStyle(fontSize: 13, height: 1.45),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

// ช่วงของไม้ผล — เลขลำดับในวงกลม + ชื่อช่วง + คำอธิบาย + ป้าย %
// ช่วงเครียดน้ำมีป้ายสีส้มเข้มให้เห็นชัดว่าเป็นช่วงงดน้ำ
class _StageTile extends StatelessWidget {
  final int number;
  final FruitStage stage;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _StageTile({
    required this.number,
    required this.stage,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    final c = stage.stress ? _stressColor : color;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: selected ? c.withValues(alpha: 0.16) : null,
              border: Border.all(
                color: selected ? c : c.withValues(alpha: 0.25),
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? c : c.withValues(alpha: 0.15),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : Text(
                          "$number",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: c,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              stage.label,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (stage.stress) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: _stressColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                "งดน้ำ",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      // คำอธิบายขึ้นเฉพาะช่วงที่กดเลือก รายการ 6 ช่วงจะได้
                      // เหลือแค่ชื่อ อ่านง่าย ไม่เป็นกำแพงตัวหนังสือ
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topLeft,
                        child: selected
                            ? Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  stage.description,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                    color: muted,
                                  ),
                                ),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "${formatMoisture(stage.targetMoisture)}%",
                  style: TextStyle(fontWeight: FontWeight.w800, color: c),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// การ์ดพืช — ไอคอนในวงสี + ป้าย % มุมขวา + คำอธิบายสั้น 2 บรรทัด
// เลือกแล้วพื้นเป็นไล่สีของพืชนั้น มีเงาเรืองสีเดียวกัน วางเมาส์แล้วขยาย
// นิดหน่อย ทุกอย่างเปลี่ยนแบบค่อยๆ ไหล (AnimatedContainer/AnimatedScale)
class _PlantTile extends StatefulWidget {
  final IconData icon;
  // true = ใช้ไอคอนผลไม้ที่วาดเอง (ไม้ผล) แทน icon
  final bool fruitIcon;
  final Color color;
  final String label;
  final String definition;
  final String? value;
  final bool selected;
  final VoidCallback onTap;

  const _PlantTile({
    required this.icon,
    this.fruitIcon = false,
    required this.color,
    required this.label,
    required this.definition,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_PlantTile> createState() => _PlantTileState();
}

class _PlantTileState extends State<_PlantTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    final c = widget.color;
    final selected = widget.selected;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hover && !selected ? 1.02 : 1,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            height: 132,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: scheme.surfaceContainerHigh,
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        c.withValues(alpha: 0.28),
                        c.withValues(alpha: 0.06),
                      ],
                    )
                  : null,
              border: Border.all(
                color: selected
                    ? c
                    : _hover
                        ? c.withValues(alpha: 0.5)
                        : scheme.outlineVariant.withValues(alpha: 0.5),
                width: selected ? 1.6 : 1,
              ),
              boxShadow: [
                if (selected || _hover)
                  BoxShadow(
                    color: c.withValues(alpha: selected ? 0.35 : 0.18),
                    blurRadius: selected ? 22 : 14,
                    offset: const Offset(0, 6),
                  ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? c : c.withValues(alpha: 0.16),
                      ),
                      child: widget.fruitIcon
                          ? Center(
                              child: FruitIcon(
                                size: 20,
                                color: selected ? Colors.white : c,
                              ),
                            )
                          : Icon(
                              widget.icon,
                              size: 20,
                              color: selected ? Colors.white : c,
                            ),
                    ),
                    const Spacer(),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: child),
                      child: selected
                          ? Icon(Icons.check_circle,
                              key: const ValueKey('check'), color: c)
                          : widget.value == null
                              ? const SizedBox(key: ValueKey('none'))
                              : Container(
                                  key: const ValueKey('value'),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: c.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    widget.value!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: c,
                                    ),
                                  ),
                                ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  selected && widget.value != null
                      ? "${widget.label} · ${widget.value}"
                      : widget.label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                // คำอธิบายสั้นบนการ์ด ให้รู้ทันทีว่าพืชของตัวเองควรเลือกอันไหน
                Expanded(
                  child: Text(
                    widget.definition,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, height: 1.35, color: muted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// กรอบของแผงรายละเอียดใต้การ์ด — แถบสีพืชด้านซ้าย + พื้นจางๆ สีเดียวกัน
class _DetailShell extends StatelessWidget {
  final Color color;
  final Widget child;

  const _DetailShell({required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: child,
    );
  }
}

class _PlantDetail extends StatelessWidget {
  final PlantProfile profile;

  const _PlantDetail({required this.profile});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    final c = profile.color;

    return _DetailShell(
      color: c,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "${profile.label} คืออะไร",
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(profile.definition, style: TextStyle(color: muted)),
          const SizedBox(height: 12),
          Text(
            "ตัวอย่างพืช",
            style: TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in profile.examples)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    e,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.water_drop_outlined, size: 18, color: c),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "${profile.care} — ตั้งความชื้นเป้าหมาย "
                  "${formatMoisture(profile.targetMoisture)}%",
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
