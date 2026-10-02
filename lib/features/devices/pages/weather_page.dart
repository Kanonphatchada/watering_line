import 'package:flutter/material.dart';
import '../../../shared/widgets/app_popup.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../shared/web/web_utils.dart';
import '../services/rain_skip.dart';
import '../widgets/farm_selector.dart';

const _weatherColor = Color(0xFF00897B); // สีเดียวกับการ์ดพยากรณ์ที่หน้าหลัก
const _rainColor = Color(0xFF1E88E5);

// หน้าพยากรณ์อากาศ — เดิมเป็น dialog ในเมนูตารางเวลา แยกออกมาเป็นหน้าของ
// ตัวเอง: สถานะที่ backend ใช้ตัดสินข้ามรดน้ำ + พยากรณ์รายชั่วโมง + ตั้งค่า
// พิกัดฟาร์ม (ค้นหาชื่อสถานที่/ตำแหน่งปัจจุบัน/กรอกเอง)
class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key});

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  String? _groupId;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ESP32')
          .where('uid', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        final groupIds = farmGroupIds(snapshot.data?.docs ?? []);
        final groupId =
            groupIds.contains(_groupId) ? _groupId : groupIds.firstOrNull;

        return Scaffold(
          appBar: AppBar(
            title: const Row(
              children: [
                Icon(Icons.cloud_outlined),
                SizedBox(width: 8),
                Text("พยากรณ์อากาศ"),
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
                  : _WeatherBody(key: ValueKey(groupId), groupId: groupId),
        );
      },
    );
  }
}

class _WeatherBody extends StatelessWidget {
  final String groupId;

  const _WeatherBody({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('device_registry')
          .doc(groupId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final reg = snapshot.data!.data() ?? {};
        final lat = (reg['farmLat'] as num?)?.toDouble();
        final lon = (reg['farmLon'] as num?)?.toDouble();

        final status = _StatusHero(registry: reg);
        final forecast = _HourlyStrip(lat: lat, lon: lon);
        final settings = _SettingsCard(groupId: groupId, registry: reg);

        return LayoutBuilder(builder: (context, c) {
          if (c.maxWidth >= 900) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 11,
                    child: Column(
                      children: [status, const SizedBox(height: 16), forecast],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(flex: 9, child: settings),
                ],
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              status,
              const SizedBox(height: 12),
              forecast,
              const SizedBox(height: 12),
              settings,
            ],
          );
        });
      },
    );
  }
}

// การ์ดสถานะใหญ่ด้านบน — บอกตรงๆ ว่าตอนนี้ระบบจะรดน้ำหรือข้าม (ตามผลที่
// backend เช็คล่าสุด ไม่ใช่พยากรณ์ที่แอปดึงเอง จะได้ตรงกับที่ระบบทำจริง)
class _StatusHero extends StatelessWidget {
  final Map<String, dynamic> registry;

  const _StatusHero({required this.registry});

  @override
  Widget build(BuildContext context) {
    final enabled = registry['rainSkipEnabled'] == true;
    final rain = registry['_rainForecast'] == true;
    final checkedAt = (registry['_weatherCheckedAt'] as Timestamp?)?.toDate();

    final (IconData icon, Color color, String title, String subtitle) = !enabled
        ? (
            Icons.cloud_off_outlined,
            Theme.of(context).colorScheme.outline,
            "ยังไม่ได้เปิดใช้",
            "เปิด \"ข้ามรดน้ำเมื่อฝนจะตก\" ด้านล่าง เพื่อประหยัดน้ำตอนฝนตก",
          )
        : rain
            ? (
                Icons.thunderstorm,
                _rainColor,
                "ฝนอาจตกเร็วๆ นี้",
                "ระบบข้ามการรดน้ำอัตโนมัติรอบนี้",
              )
            : (
                Icons.wb_sunny_outlined,
                _weatherColor,
                "ไม่มีฝนใน 3 ชม.ข้างหน้า",
                "รดน้ำอัตโนมัติตามปกติ",
              );

    String? checkedText;
    if (enabled && checkedAt != null) {
      final mins = DateTime.now().difference(checkedAt).inMinutes;
      checkedText =
          mins < 1 ? "เช็คล่าสุดเมื่อสักครู่" : "เช็คล่าสุด $mins นาทีก่อน";
    }

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withValues(alpha: 0.28), Colors.transparent],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -24,
              top: -24,
              child:
                  Icon(icon, size: 170, color: color.withValues(alpha: 0.10)),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.18),
                    ),
                    child: Icon(icon, size: 34, color: color),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(subtitle, style: const TextStyle(fontSize: 14)),
                        if (checkedText != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            checkedText,
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  Theme.of(context).textTheme.bodySmall?.color,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// พยากรณ์รายชั่วโมง 12 ชม.ข้างหน้า เลื่อนแนวนอน — 3 ช่องแรกคือช่วงที่ระบบใช้
// ตัดสินข้ามรดน้ำ (ไฮไลต์ไว้ให้เห็น)
class _HourlyStrip extends StatefulWidget {
  final double? lat;
  final double? lon;

  const _HourlyStrip({required this.lat, required this.lon});

  @override
  State<_HourlyStrip> createState() => _HourlyStripState();
}

class _HourlyStripState extends State<_HourlyStrip> {
  Future<List<HourlyForecast>>? _future;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant _HourlyStrip old) {
    super.didUpdateWidget(old);
    if (old.lat != widget.lat || old.lon != widget.lon) _fetch();
  }

  void _fetch() {
    _future = widget.lat == null || widget.lon == null
        ? null
        : fetchHourlyForecast(widget.lat!, widget.lon!);
  }

  IconData _iconFor(HourlyForecast h) {
    if (h.rainProbability >= 70) return Icons.thunderstorm;
    if (h.rainProbability >= 40) return Icons.grain;
    final night = h.time.hour < 6 || h.time.hour >= 18;
    return night ? Icons.nights_stay_outlined : Icons.wb_sunny_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "12 ชั่วโมงข้างหน้า",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                if (_future != null)
                  IconButton(
                    tooltip: "โหลดใหม่",
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: () => setState(_fetch),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_future == null)
              Text(
                "ตั้งพิกัดฟาร์มก่อน แล้วพยากรณ์จะขึ้นตรงนี้",
                style: TextStyle(color: muted),
              )
            else
              FutureBuilder<List<HourlyForecast>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const SizedBox(
                      height: 120,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final hours = snap.data ?? [];
                  if (snap.hasError || hours.isEmpty) {
                    return Text("ดึงพยากรณ์ไม่สำเร็จ ลองโหลดใหม่",
                        style: TextStyle(color: muted));
                  }
                  return SizedBox(
                    height: 132,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: hours.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final h = hours[i];
                        final checked = i < 3;
                        final rainy = h.rainProbability >= 70;
                        final c = rainy ? _rainColor : _weatherColor;
                        return Container(
                          width: 72,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: c.withValues(alpha: checked ? 0.16 : 0.06),
                            border: Border.all(
                              color: checked
                                  ? c.withValues(alpha: 0.6)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                i == 0
                                    ? "ตอนนี้"
                                    : "${h.time.hour.toString().padLeft(2, '0')}:00",
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Icon(_iconFor(h), color: c),
                              Text(
                                "${h.temperature.round()}°",
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.water_drop,
                                      size: 11, color: _rainColor),
                                  Text(
                                    "${h.rainProbability}%",
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: rainy ? _rainColor : muted,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            if (_future != null) ...[
              const SizedBox(height: 10),
              Text(
                "ช่องที่มีกรอบ = 3 ชม.ที่ระบบใช้ตัดสิน · ข้ามรดน้ำเมื่อโอกาสฝน "
                "≥ 70% และปริมาณรวม ≥ 1 มม.",
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ตั้งค่า: เปิด/ปิดข้ามรดน้ำ + พิกัดฟาร์ม — ค้นหาชื่อสถานที่แล้วเลือกจากรายการ
// ในหน้าเลย (ไม่เด้ง dialog ซ้อน) ใช้ตำแหน่งปัจจุบันได้ หรือกรอกพิกัดเองก็ได้
class _SettingsCard extends StatefulWidget {
  final String groupId;
  final Map<String, dynamic> registry;

  const _SettingsCard({required this.groupId, required this.registry});

  @override
  State<_SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<_SettingsCard> {
  late bool _enabled = widget.registry['rainSkipEnabled'] == true;
  late final _latController = TextEditingController(
    text: widget.registry['farmLat']?.toString() ?? '',
  );
  late final _lonController = TextEditingController(
    text: widget.registry['farmLon']?.toString() ?? '',
  );
  final _placeController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  String? _placeError;
  String? _pickedPlace;
  bool _searching = false;
  bool _saving = false;

  @override
  void dispose() {
    _latController.dispose();
    _lonController.dispose();
    _placeController.dispose();
    super.dispose();
  }

  double? get _lat => double.tryParse(_latController.text.trim());
  double? get _lon => double.tryParse(_lonController.text.trim());

  bool get _validCoords =>
      _lat != null &&
      _lon != null &&
      _lat! >= -90 &&
      _lat! <= 90 &&
      _lon! >= -180 &&
      _lon! <= 180;

  bool get _changed =>
      _enabled != (widget.registry['rainSkipEnabled'] == true) ||
      _lat != (widget.registry['farmLat'] as num?)?.toDouble() ||
      _lon != (widget.registry['farmLon'] as num?)?.toDouble();

  Future<void> _search() async {
    final q = _placeController.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _placeError = null;
    });
    try {
      final r = await searchPlaces(q);
      setState(() {
        _results = r;
        _placeError = r.isEmpty ? "ไม่พบสถานที่นี้" : null;
      });
    } catch (_) {
      setState(() => _placeError = "ค้นหาไม่สำเร็จ ลองอีกครั้ง");
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    final pos = await getCurrentPosition();
    if (!mounted) return;
    if (pos == null) {
      showErrorPopup(
          context, "ขอตำแหน่งไม่สำเร็จ (ต้องอนุญาตสิทธิ์ตำแหน่งในเบราว์เซอร์)");
      return;
    }
    setState(() {
      _latController.text = '${pos['lat']}';
      _lonController.text = '${pos['lon']}';
      _pickedPlace = "ตำแหน่งปัจจุบัน";
      _results = [];
    });
  }

  Future<void> _save() async {
    if (_enabled && !_validCoords) {
      showAppPopup(
          context, "ยังไม่มีพิกัดฟาร์ม ค้นหาสถานที่หรือใช้ตำแหน่งปัจจุบันก่อน",
          kind: PopupKind.info);
      return;
    }
    setState(() => _saving = true);
    try {
      await saveRainSkip(widget.groupId,
          enabled: _enabled, lat: _lat, lon: _lon);
      if (!mounted) return;
      showSuccessPopup(context, "บันทึกการตั้งค่าพยากรณ์อากาศแล้ว");
    } catch (err) {
      if (!mounted) return;
      showErrorPopup(context, "บันทึกไม่สำเร็จ: $err");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "ตั้งค่า",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                "ข้ามรดน้ำเมื่อฝนจะตก",
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text("เช็คฝน 3 ชม.ข้างหน้าก่อนรดน้ำทุกรอบ"),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            const Divider(height: 24),
            Row(
              children: [
                Icon(Icons.place_outlined, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                const Text(
                  "ตำแหน่งฟาร์ม",
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _validCoords
                  ? "${_pickedPlace != null ? '$_pickedPlace · ' : ''}"
                      "${_lat!.toStringAsFixed(4)}, ${_lon!.toStringAsFixed(4)}"
                  : "ยังไม่ได้ตั้งพิกัด",
              style: TextStyle(fontSize: 13, color: muted),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _placeController,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: "ค้นหาอำเภอ/จังหวัด",
                      prefixIcon: const Icon(Icons.search, size: 20),
                      errorText: _placeError,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _searching ? null : _search,
                  child: _searching
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("ค้นหา"),
                ),
              ],
            ),
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final r in _results)
                    ActionChip(
                      avatar: const Icon(Icons.place, size: 16),
                      label: Text(placeLabel(r)),
                      onPressed: () => setState(() {
                        _latController.text = '${r['latitude']}';
                        _lonController.text = '${r['longitude']}';
                        _pickedPlace = r['name'] as String?;
                        _results = [];
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _useCurrentLocation,
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text("ใช้ตำแหน่งปัจจุบัน"),
            ),
            // กรอกพิกัดเองซ่อนไว้ — คนส่วนใหญ่ไม่รู้ละติจูด/ลองจิจูดของตัวเอง
            Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text("กรอกพิกัดเอง",
                    style: TextStyle(fontSize: 13, color: muted)),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _latController,
                          onChanged: (_) => setState(() => _pickedPlace = null),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          decoration: const InputDecoration(
                            labelText: "ละติจูด",
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _lonController,
                          onChanged: (_) => setState(() => _pickedPlace = null),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          decoration: const InputDecoration(
                            labelText: "ลองจิจูด",
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _changed && !_saving ? _save : null,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_changed ? "บันทึก" : "บันทึกแล้ว"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
