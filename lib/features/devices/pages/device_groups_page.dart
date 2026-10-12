import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../shared/widgets/app_popup.dart';
import '../services/device_groups.dart';
import '../widgets/group_style.dart';

Future<bool> _save(
  BuildContext context,
  List<DeviceGroup> Function(List<DeviceGroup>) change,
  String okMessage,
) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return false;
  try {
    await updateDeviceGroups(uid, change);
    if (context.mounted) showSuccessPopup(context, okMessage);
    return true;
  } on FirebaseException catch (e) {
    if (context.mounted) {
      showErrorPopup(
        context,
        e.code == 'permission-denied'
            ? "บันทึกกลุ่มไม่ได้: ไม่มีสิทธิ์เขียนข้อมูลผู้ใช้"
            : "บันทึกกลุ่มไม่สำเร็จ ลองใหม่อีกครั้ง",
      );
    }
  } catch (_) {
    if (context.mounted) {
      showErrorPopup(context, "บันทึกกลุ่มไม่สำเร็จ ลองใหม่อีกครั้ง");
    }
  }
  return false;
}

// เปิดกล่องสร้าง (existing == null) หรือแก้ไขกลุ่ม แล้วบันทึกให้เลย — ใช้ร่วม
// กันทั้งหน้าหลัก หน้ารายละเอียดกลุ่ม และหน้าจัดการกลุ่ม คืน true ถ้าบันทึกสำเร็จ
Future<bool> openGroupEditor(
  BuildContext context, {
  required List<QueryDocumentSnapshot> docs,
  required List<DeviceGroup> groups,
  DeviceGroup? existing,
}) async {
  final result = await showDialog<_GroupEditResult>(
    context: context,
    builder: (_) => _GroupEditDialog(
      docs: docs,
      groups: groups,
      existing: existing,
    ),
  );
  if (result == null || !context.mounted) return false;

  if (existing == null) {
    final id = newGroupId();
    return _save(
      context,
      (cur) => setGroupMembers(
        addGroup(
          cur,
          DeviceGroup(
            id: id,
            name: result.name,
            iconKey: result.iconKey,
            colorIndex: result.colorIndex,
          ),
        ),
        id,
        result.deviceIds,
      ),
      "สร้างกลุ่ม \"${result.name}\" แล้ว",
    );
  }
  return _save(
    context,
    (cur) => setGroupMembers(
      restyleGroup(
        renameGroup(cur, existing.id, result.name),
        existing.id,
        iconKey: result.iconKey,
        colorIndex: result.colorIndex,
      ),
      existing.id,
      result.deviceIds,
    ),
    "บันทึกกลุ่มแล้ว",
  );
}

// ถามยืนยันแล้วลบกลุ่ม (อุปกรณ์ในกลุ่มไม่ถูกลบ แค่กลับไปเป็น "ไม่ได้จัดกลุ่ม")
// คืน true ถ้าลบสำเร็จ
Future<bool> confirmAndDeleteGroup(
  BuildContext context,
  DeviceGroup group,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text("ลบกลุ่ม \"${group.name}\"?"),
      content: const Text(
        "อุปกรณ์ในกลุ่มนี้จะไม่ถูกลบ แค่กลับไปเป็น \"ไม่ได้จัดกลุ่ม\"",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text("ยกเลิก"),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(context, true),
          child: const Text("ลบกลุ่ม"),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  return _save(context, (cur) => removeGroup(cur, group.id), "ลบกลุ่มแล้ว");
}

// หน้ารายการจัดการกลุ่มทั้งหมด (เปิดจากไอคอนโฟลเดอร์ในแถบซ้าย)
class DeviceGroupsPage extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;

  const DeviceGroupsPage({super.key, required this.docs});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final existingIds = docs.map((d) => d.id).toSet();

    return Scaffold(
      appBar: AppBar(title: const Text("กลุ่มอุปกรณ์")),
      body: StreamBuilder<List<DeviceGroup>>(
        stream: watchDeviceGroups(uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("เกิดข้อผิดพลาด: ${snapshot.error}"));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final groups = pruneMissingDevices(snapshot.data!, existingIds);
          final groupedCount =
              groups.fold<int>(0, (total, g) => total + g.deviceIds.length);
          final muted = Theme.of(context).textTheme.bodySmall?.color;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    "จัดอุปกรณ์เป็นกลุ่มตามชนิดพืชที่ปลูก ตั้งชื่อและเลือกไอคอนเอง"
                    "ได้ อุปกรณ์หนึ่งตัวอยู่ได้กลุ่มเดียว",
                    style: TextStyle(fontSize: 13, color: muted),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          "จัดกลุ่มแล้ว $groupedCount จาก ${docs.length} ตัว",
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => openGroupEditor(
                          context,
                          docs: docs,
                          groups: groups,
                        ),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text("สร้างกลุ่มใหม่"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (groups.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        children: [
                          Icon(
                            Icons.folder_open_rounded,
                            size: 48,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 8),
                          const Text("ยังไม่มีกลุ่ม"),
                          Text(
                            "กด \"สร้างกลุ่มใหม่\" เช่น ผักกาด, กวางตุ้ง",
                            style: TextStyle(fontSize: 13, color: muted),
                          ),
                        ],
                      ),
                    ),
                  for (final g in groups)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                GroupBadge(
                                  iconKey: g.iconKey,
                                  colorIndex: g.colorIndex,
                                  size: 40,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    g.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: "แก้ไขกลุ่ม",
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => openGroupEditor(
                                    context,
                                    docs: docs,
                                    groups: groups,
                                    existing: g,
                                  ),
                                ),
                                IconButton(
                                  tooltip: "ลบกลุ่ม",
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  onPressed: () =>
                                      confirmAndDeleteGroup(context, g),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (g.deviceIds.isEmpty)
                              Text(
                                "ยังไม่มีอุปกรณ์ในกลุ่มนี้",
                                style: TextStyle(fontSize: 13, color: muted),
                              )
                            else
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final id in g.deviceIds)
                                    Chip(
                                      label: Text(id),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GroupEditResult {
  final String name;
  final List<String> deviceIds;
  final String iconKey;
  final int colorIndex;

  const _GroupEditResult(
    this.name,
    this.deviceIds,
    this.iconKey,
    this.colorIndex,
  );
}

class _GroupEditDialog extends StatefulWidget {
  final List<QueryDocumentSnapshot> docs;
  final List<DeviceGroup> groups;
  final DeviceGroup? existing;

  const _GroupEditDialog({
    required this.docs,
    required this.groups,
    this.existing,
  });

  @override
  State<_GroupEditDialog> createState() => _GroupEditDialogState();
}

class _GroupEditDialogState extends State<_GroupEditDialog> {
  late final _nameController =
      TextEditingController(text: widget.existing?.name ?? '');
  late final Set<String> _checked = {...?widget.existing?.deviceIds};
  late String _iconKey = widget.existing?.iconKey ?? defaultGroupIconKey;
  // กลุ่มใหม่เริ่มที่สีถัดจากกลุ่มล่าสุด ให้การ์ดข้างกันไม่สีซ้ำกันหมด
  late int _colorIndex =
      widget.existing?.colorIndex ?? widget.groups.length % kGroupColors.length;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final error = validateGroupName(
      _nameController.text,
      widget.groups,
      exceptId: widget.existing?.id,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(
      context,
      _GroupEditResult(
        _nameController.text.trim(),
        _checked.toList(),
        _iconKey,
        _colorIndex,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    return AlertDialog(
      title: Text(widget.existing == null ? "สร้างกลุ่มใหม่" : "แก้ไขกลุ่ม"),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: GroupBadge(
                      iconKey: _iconKey,
                      colorIndex: _colorIndex,
                      size: 52,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      autofocus: widget.existing == null,
                      maxLength: maxGroupNameLength,
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: "ชื่อกลุ่ม",
                        hintText: "เช่น ผักกาด, กวางตุ้ง",
                        errorText: _error,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GroupStylePicker(
                iconKey: _iconKey,
                colorIndex: _colorIndex,
                onIconChanged: (k) => setState(() => _iconKey = k),
                onColorChanged: (i) => setState(() => _colorIndex = i),
              ),
              const SizedBox(height: 18),
              const Text(
                "อุปกรณ์ในกลุ่มนี้",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (widget.docs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text("ยังไม่มีอุปกรณ์"),
                )
              else
                for (final d in widget.docs)
                  Builder(builder: (context) {
                    final other = groupOfDevice(widget.groups, d.id);
                    final inOther =
                        other != null && other.id != widget.existing?.id;
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _checked.contains(d.id),
                      title: Text(d.id),
                      subtitle: inOther
                          ? Text(
                              _checked.contains(d.id)
                                  ? "จะย้ายมาจากกลุ่ม \"${other.name}\""
                                  : "อยู่ในกลุ่ม \"${other.name}\"",
                              style: TextStyle(fontSize: 12, color: muted),
                            )
                          : null,
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _checked.add(d.id);
                        } else {
                          _checked.remove(d.id);
                        }
                      }),
                    );
                  }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("ยกเลิก"),
        ),
        FilledButton(onPressed: _submit, child: const Text("บันทึก")),
      ],
    );
  }
}
