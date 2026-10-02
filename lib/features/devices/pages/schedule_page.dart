import 'package:flutter/material.dart';
import '../../../shared/widgets/app_popup.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/device_schedule.dart';
import '../services/farm_schedule.dart';
import '../utils/schedule_utils.dart';
import '../widgets/farm_selector.dart';

const _allowColor = Color(0xFF43A047);
const _blockColor = Color(0xFFE53935);

// หน้าตารางเวลา — รวม "ตั้งเวลาทั้งฟาร์ม" กับ "สรุปตารางเวลา" ไว้หน้าเดียว
// (เดิมเป็น dialog + หน้าแยก) จอกว้างวางคู่กันซ้าย/ขวาเห็นครบไม่ต้องเลื่อน
// จอแคบสลับด้วยแท็บด้านบน ฟัง ESP32 แบบ stream เอง ค่าในสรุปจะอัปเดตทันที
// หลังแก้ตารางเวลาของอุปกรณ์ ไม่ต้องปิดเปิดหน้าใหม่
class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  String? _groupId;
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ESP32')
          .where('uid', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        final allDocs = snapshot.data?.docs ?? [];
        final groupIds = farmGroupIds(allDocs);
        final groupId =
            groupIds.contains(_groupId) ? _groupId : groupIds.firstOrNull;
        final docs = allDocs
            .where(
                (d) => (d.data() as Map<String, dynamic>)['groupId'] == groupId)
            .toList();

        return Scaffold(
          appBar: AppBar(
            title: const Row(
              children: [
                Icon(Icons.schedule),
                SizedBox(width: 8),
                Text("ตารางเวลา"),
              ],
            ),
            actions: [
              if (groupId != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: FarmSelector(
                      groupIds: groupIds,
                      groupId: groupId,
                      onChanged: (g) => setState(() => _groupId = g),
                    ),
                  ),
                ),
            ],
          ),
          body: !snapshot.hasData
              ? const Center(child: CircularProgressIndicator())
              : groupId == null
                  ? const Center(child: Text("ไม่พบกลุ่ม/ฟาร์มของอุปกรณ์เลย"))
                  : LayoutBuilder(builder: (context, c) {
                      final editor = _FarmScheduleEditor(
                        key: ValueKey(groupId),
                        groupId: groupId,
                        docs: docs,
                      );
                      final overview = _ScheduleOverview(docs: docs);

                      if (c.maxWidth >= 900) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 11, child: editor),
                              const SizedBox(width: 16),
                              Expanded(flex: 9, child: overview),
                            ],
                          ),
                        );
                      }

                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<int>(
                                segments: const [
                                  ButtonSegment(
                                    value: 0,
                                    icon: Icon(Icons.tune),
                                    label: Text("ตั้งเวลาทั้งฟาร์ม"),
                                  ),
                                  ButtonSegment(
                                    value: 1,
                                    icon: Icon(Icons.fact_check_outlined),
                                    label: Text("สรุปตารางเวลา"),
                                  ),
                                ],
                                selected: {_tab},
                                showSelectedIcon: false,
                                onSelectionChanged: (s) =>
                                    setState(() => _tab = s.first),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: IndexedStack(
                                index: _tab,
                                children: [editor, overview],
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// ตั้งเวลาทั้งฟาร์ม
// ---------------------------------------------------------------------------

class _FarmScheduleEditor extends StatefulWidget {
  final String groupId;
  final List<QueryDocumentSnapshot> docs;

  const _FarmScheduleEditor({
    super.key,
    required this.groupId,
    required this.docs,
  });

  @override
  State<_FarmScheduleEditor> createState() => _FarmScheduleEditorState();
}

class _FarmScheduleEditorState extends State<_FarmScheduleEditor> {
  FarmSchedule? _saved;
  FarmSchedule? _draft;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // อ่านครั้งเดียวตอนเข้าหน้า/เปลี่ยนฟาร์ม (ไม่ใช้ stream) กันค่าที่กำลังแก้
  // อยู่ถูกทับทุกครั้งที่ backend เขียน _rainForecast ฯลฯ ลง doc เดียวกัน
  Future<void> _load() async {
    final doc = await FirebaseFirestore.instance
        .collection('device_registry')
        .doc(widget.groupId)
        .get();
    if (!mounted) return;
    final s = FarmSchedule.fromRegistry(doc.data() ?? {});
    setState(() {
      _saved = s;
      _draft = s.copy();
    });
  }

  Future<void> _pickTime(
    TimeOfDay initial,
    ValueChanged<TimeOfDay> onPicked,
  ) async {
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) setState(() => onPicked(picked));
  }

  Future<void> _save() async {
    final draft = _draft!;
    setState(() => _saving = true);
    try {
      await saveFarmSchedule(widget.groupId, draft, widget.docs);
      if (!mounted) return;
      setState(() {
        _saved = draft.copy();
        _saving = false;
      });
      showSuccessPopup(context, "บันทึกตารางเวลาทั้งฟาร์มแล้ว");
    } catch (err) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorPopup(context, "บันทึกไม่สำเร็จ: $err");
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    if (draft == null) {
      return const Card(child: Center(child: CircularProgressIndicator()));
    }

    final overrideCount = widget.docs
        .where((d) =>
            (d.data() as Map<String, dynamic>)['scheduleOverride'] == true)
        .length;
    final followCount = widget.docs.length - overrideCount;
    final changed = !draft.sameAs(_saved!);
    final now = TimeOfDay.now();
    final allowedNow = draft.allowedAtMinute(now.hour * 60 + now.minute);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "ตั้งเวลาทั้งฟาร์ม",
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "ใช้กับ $followCount อุปกรณ์"
                              "${overrideCount > 0 ? ' · $overrideCount ตัวตั้งเฉพาะเอง (ไม่ถูกทับ)' : ''}",
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: draft.enabled,
                        onChanged: (v) => setState(() => draft.enabled = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ScheduleTimeline(schedule: draft),
                  const SizedBox(height: 10),
                  _NowStatus(enabled: draft.enabled, allowed: allowedNow),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: !draft.enabled
                        ? const SizedBox(width: double.infinity)
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: SegmentedButton<String>(
                                  segments: const [
                                    ButtonSegment(
                                      value: 'allow',
                                      icon: Icon(Icons.water_drop_outlined),
                                      label: Text("รดได้เฉพาะช่วงนี้"),
                                    ),
                                    ButtonSegment(
                                      value: 'block',
                                      icon: Icon(Icons.block),
                                      label: Text("ห้ามรดช่วงนี้"),
                                    ),
                                  ],
                                  selected: {draft.mode},
                                  showSelectedIcon: false,
                                  onSelectionChanged: (s) =>
                                      setState(() => draft.mode = s.first),
                                ),
                              ),
                              const SizedBox(height: 14),
                              _TimeRangeRow(
                                color: draft.mode == 'block'
                                    ? _blockColor
                                    : _allowColor,
                                start: draft.start,
                                end: draft.end,
                                onStart: () => _pickTime(
                                    draft.start, (t) => draft.start = t),
                                onEnd: () =>
                                    _pickTime(draft.end, (t) => draft.end = t),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  const Icon(Icons.do_not_disturb_on_outlined,
                                      size: 20, color: _blockColor),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      "ช่วงห้ามรดพิเศษ",
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  Switch(
                                    value: draft.exceptEnabled,
                                    onChanged: (v) =>
                                        setState(() => draft.exceptEnabled = v),
                                  ),
                                ],
                              ),
                              Text(
                                "ห้ามรดช่วงนี้เสมอ เช่น เที่ยงแดดจัด",
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                              if (draft.exceptEnabled) ...[
                                const SizedBox(height: 10),
                                _TimeRangeRow(
                                  color: _blockColor,
                                  start: draft.exceptStart,
                                  end: draft.exceptEnd,
                                  onStart: () => _pickTime(draft.exceptStart,
                                      (t) => draft.exceptStart = t),
                                  onEnd: () => _pickTime(draft.exceptEnd,
                                      (t) => draft.exceptEnd = t),
                                ),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
          // แถบบันทึกติดล่างการ์ด — กดได้เฉพาะตอนมีการแก้ไข
          Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    changed ? "มีการแก้ไขที่ยังไม่บันทึก" : "บันทึกแล้ว",
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
                if (changed)
                  TextButton(
                    onPressed: () => setState(() => _draft = _saved!.copy()),
                    child: const Text("ยกเลิก"),
                  ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: changed && !_saving ? _save : null,
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
        ],
      ),
    );
  }
}

class _NowStatus extends StatelessWidget {
  final bool enabled;
  final bool allowed;

  const _NowStatus({required this.enabled, required this.allowed});

  @override
  Widget build(BuildContext context) {
    final c = !enabled
        ? Theme.of(context).colorScheme.outline
        : allowed
            ? _allowColor
            : _blockColor;
    final text = !enabled
        ? "ไม่ได้ใช้ตารางเวลา รดตามความชื้นได้ตลอดวัน"
        : allowed
            ? "ตอนนี้อยู่ในช่วงที่รดน้ำได้"
            : "ตอนนี้อยู่ในช่วงห้ามรดน้ำ";
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c),
        ),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(fontSize: 13, color: c)),
      ],
    );
  }
}

// ช่องเวลาเริ่ม → สิ้นสุด แบบปุ่มใหญ่สองอันข้างกัน แตะแล้วเปิดตัวเลือกเวลา
class _TimeRangeRow extends StatelessWidget {
  final Color color;
  final TimeOfDay start;
  final TimeOfDay end;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  const _TimeRangeRow({
    required this.color,
    required this.start,
    required this.end,
    required this.onStart,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    Widget box(String label, TimeOfDay t, VoidCallback onTap) => Expanded(
          child: Material(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                    Text(
                      formatHHmm(t),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

    return Row(
      children: [
        box("เริ่ม", start, onStart),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Icon(Icons.arrow_forward, color: color),
        ),
        box("สิ้นสุด", end, onEnd),
      ],
    );
  }
}

// แถบเวลา 24 ชม. — เขียว = รดได้, แดง = ห้ามรด, เส้นขาว = เวลาตอนนี้
// เห็นภาพรวมทั้งวันทันทีว่าตั้งไว้แบบไหน (รวมช่วงห้ามรดพิเศษ/ข้ามเที่ยงคืน)
class ScheduleTimeline extends StatelessWidget {
  final FarmSchedule schedule;

  const ScheduleTimeline({super.key, required this.schedule});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    final now = TimeOfDay.now();

    return Column(
      children: [
        SizedBox(
          height: 28,
          width: double.infinity,
          child: CustomPaint(
            painter: _TimelinePainter(
              schedule: schedule,
              nowMinute: now.hour * 60 + now.minute,
              idle: Theme.of(context).colorScheme.outline,
              marker: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final h in ['00', '06', '12', '18', '24'])
              Text("$h:00", style: TextStyle(fontSize: 10, color: muted)),
          ],
        ),
      ],
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final FarmSchedule schedule;
  final int nowMinute;
  final Color idle;
  final Color marker;

  _TimelinePainter({
    required this.schedule,
    required this.nowMinute,
    required this.idle,
    required this.marker,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    canvas.save();
    canvas.clipRRect(rrect);

    Color colorAt(int m) => !schedule.enabled
        ? idle.withValues(alpha: 0.35)
        : schedule.allowedAtMinute(m)
            ? _allowColor
            : _blockColor.withValues(alpha: 0.75);

    // รวมนาทีที่สีเดียวกันติดกันเป็นก้อนเดียวแล้ววาดทีเดียว — วาดทีละช่อง
    // เล็กๆ ซ้อนกันจะเห็นเส้นลายตรงรอยต่อ (สีโปร่งแสงทับกันเข้มขึ้น)
    var runStart = 0;
    var runColor = colorAt(0);
    for (var m = 1; m <= 1440; m++) {
      final c = m < 1440 ? colorAt(m) : null;
      if (c == runColor) continue;
      canvas.drawRect(
        Rect.fromLTRB(
          size.width * runStart / 1440,
          0,
          size.width * m / 1440,
          size.height,
        ),
        Paint()..color = runColor,
      );
      runStart = m;
      if (c != null) runColor = c;
    }
    canvas.restore();

    final x = size.width * nowMinute / 1440;
    canvas.drawLine(
      Offset(x, -3),
      Offset(x, size.height + 3),
      Paint()
        ..color = marker
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_TimelinePainter old) => true;
}

// ---------------------------------------------------------------------------
// สรุปตารางเวลา
// ---------------------------------------------------------------------------

class _ScheduleOverview extends StatefulWidget {
  final List<QueryDocumentSnapshot> docs;

  const _ScheduleOverview({required this.docs});

  @override
  State<_ScheduleOverview> createState() => _ScheduleOverviewState();
}

class _ScheduleOverviewState extends State<_ScheduleOverview> {
  // null = ทั้งหมด
  String? _filter;
  String _query = '';

  // ตรรกะแบ่งหมวดเดียวกับ dialog ตั้งเวลารายอุปกรณ์ (openDeviceScheduleDialog)
  static String _categoryOf(Map<String, dynamic> data) {
    if (data['scheduleOverride'] != true) return 'farm';
    return data['scheduleEnabled'] == true ? 'custom' : 'none';
  }

  static const _categories = [
    ('farm', 'ตามฟาร์ม', Icons.groups_outlined, Color(0xFF1E88E5)),
    ('custom', 'ตั้งเฉพาะ', Icons.edit_calendar_outlined, Color(0xFF8E24AA)),
    ('none', 'ไม่ใช้ตาราง', Icons.block_outlined, Color(0xFF757575)),
  ];

  String _describe(Map<String, dynamic> data) {
    switch (_categoryOf(data)) {
      case 'farm':
        return "ใช้ตารางเวลาของฟาร์ม";
      case 'none':
        return "รดตามความชื้นได้ตลอดวัน";
      default:
        final mode = data['scheduleMode'] == 'block' ? "ห้ามรด" : "รดได้";
        final s = data['scheduleStart'] ?? '--:--';
        final e = data['scheduleEnd'] ?? '--:--';
        final except = data['scheduleExceptEnabled'] == true
            ? " · เว้น ${data['scheduleExceptStart']}–${data['scheduleExceptEnd']}"
            : "";
        return "$mode $s–$e$except";
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    final counts = {for (final c in _categories) c.$1: 0};
    for (final d in widget.docs) {
      final k = _categoryOf(d.data() as Map<String, dynamic>);
      counts[k] = counts[k]! + 1;
    }

    final q = _query.trim().toLowerCase();
    final rows = widget.docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      return (_filter == null || _categoryOf(data) == _filter) &&
          (q.isEmpty || d.id.toLowerCase().contains(q));
    }).toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "สรุปตารางเวลา",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              "แตะหมวดเพื่อกรอง · แตะอุปกรณ์เพื่อแก้ตารางเวลาเฉพาะตัว",
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 14),
            // ช่องนับจำนวนแต่ละหมวด ทำหน้าที่เป็นตัวกรองไปด้วย (กดซ้ำ = ดูทั้งหมด)
            Row(
              children: [
                for (final (i, (key, label, icon, color))
                    in _categories.indexed)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                      child: _CountTile(
                        label: label,
                        icon: icon,
                        color: color,
                        count: counts[key]!,
                        selected: _filter == key,
                        onTap: () => setState(
                            () => _filter = _filter == key ? null : key),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                isDense: true,
                hintText: "ค้นหาชื่ออุปกรณ์...",
                prefixIcon: Icon(Icons.search, size: 20),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child:
                          Text("ไม่พบอุปกรณ์", style: TextStyle(color: muted)),
                    )
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final d = rows[i];
                        final data = d.data() as Map<String, dynamic>;
                        final cat = _categories
                            .firstWhere((c) => c.$1 == _categoryOf(data));
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: cat.$4.withValues(alpha: 0.15),
                            child: Icon(cat.$3, size: 16, color: cat.$4),
                          ),
                          title: Text(
                            d.id,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            _describe(data),
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              openDeviceScheduleDialog(context, d.id, data),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _CountTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: color.withValues(alpha: selected ? 0.22 : 0.08),
            border: Border.all(
              color: selected ? color : color.withValues(alpha: 0.25),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 4),
              Text(
                "$count",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
