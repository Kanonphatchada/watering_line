import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../shared/widgets/app_popup.dart';
import '../services/farm_members.dart';

// จัดการสมาชิกของฟาร์ม — เจ้าของเชิญคน (ด้วยรหัสอายุ 24 ชม.) ตั้งสิทธิ์รายคน และ
// ลบสมาชิกได้ สมาชิกเห็นรายชื่อและออกจากฟาร์มเองได้
class FarmMembersPage extends StatelessWidget {
  final String farmId;

  const FarmMembersPage({super.key, required this.farmId});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text("สมาชิกของฟาร์ม")),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('device_registry')
            .doc(farmId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text("เปิดข้อมูลฟาร์มนี้ไม่ได้"));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final registry = snapshot.data!.data();
          if (registry == null) {
            return const Center(child: Text("ไม่พบฟาร์มนี้แล้ว"));
          }
          final isOwner = registry['ownerUid'] == uid;
          final members = FarmMember.parseAll(registry);
          final muted = Theme.of(context).textTheme.bodySmall?.color;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      const Icon(Icons.agriculture_outlined, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          farmId,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      _RoleChip(isOwner: isOwner, uid: uid, members: members),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isOwner
                        ? "เชิญคนมาดูแลฟาร์มด้วยกัน และเลือกได้ว่าแต่ละคนทำอะไรได้บ้าง"
                        : "คุณเป็นสมาชิกของฟาร์มนี้ สิทธิ์ของคุณตั้งโดยเจ้าของฟาร์ม",
                    style: TextStyle(fontSize: 13, color: muted),
                  ),
                  const SizedBox(height: 16),
                  if (isOwner)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => _invite(context),
                        icon: const Icon(Icons.person_add_alt_1_outlined,
                            size: 18),
                        label: const Text("เชิญสมาชิก"),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.workspace_premium_outlined),
                          ),
                          title: Text(isOwner ? "คุณ" : "เจ้าของฟาร์ม"),
                          subtitle: const Text("เจ้าของ · ทำได้ทุกอย่าง"),
                        ),
                        for (final m in members) ...[
                          const Divider(height: 1),
                          _MemberTile(
                            member: m,
                            isMe: m.uid == uid,
                            canManage: isOwner,
                            onLevel: (level) => _changeLevel(context, m, level),
                            onRemove: () => _remove(context, m),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (members.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          isOwner
                              ? "ยังไม่มีสมาชิก กด \"เชิญสมาชิก\" เพื่อสร้างรหัสเชิญ"
                              : "",
                          style: TextStyle(fontSize: 13, color: muted),
                        ),
                      ),
                    ),
                  if (!isOwner && members.any((m) => m.uid == uid)) ...[
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      style:
                          OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () => _leave(context),
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text("ออกจากฟาร์มนี้"),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    String loading,
    Future<void> Function() work,
    String ok,
  ) async {
    final close = showLoadingPopup(context, loading);
    try {
      await work();
      close();
      if (context.mounted) showSuccessPopup(context, ok);
    } on FarmApiException catch (e) {
      close();
      if (context.mounted) showErrorPopup(context, e.message);
    }
  }

  Future<void> _invite(BuildContext context) async {
    final level = await showDialog<MemberLevel>(
      context: context,
      builder: (_) => const _LevelPickerDialog(
        title: "เชิญสมาชิก",
        subtitle: "เลือกสิทธิ์ที่คนนี้จะได้เมื่อเข้าร่วม (เปลี่ยนทีหลังได้)",
        initial: MemberLevel.viewer,
        confirmLabel: "สร้างรหัสเชิญ",
      ),
    );
    if (level == null || !context.mounted) return;

    final close = showLoadingPopup(context, "กำลังสร้างรหัสเชิญ...");
    try {
      final invite = await createFarmInvite(farmId, level);
      close();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _InviteCodeDialog(invite: invite, level: level),
      );
    } on FarmApiException catch (e) {
      close();
      if (context.mounted) showErrorPopup(context, e.message);
    }
  }

  Future<void> _changeLevel(
    BuildContext context,
    FarmMember m,
    MemberLevel level,
  ) async {
    if (level == m.level) return;
    await _run(
      context,
      "กำลังเปลี่ยนสิทธิ์...",
      () => setMemberLevel(farmId, m.uid, level),
      "เปลี่ยนสิทธิ์เป็น \"${levelLabel(level)}\" แล้ว",
    );
  }

  Future<void> _remove(BuildContext context, FarmMember m) async {
    final name = m.name.isEmpty ? "สมาชิกคนนี้" : m.name;
    final ok = await _confirm(
      context,
      title: "ลบ $name ออกจากฟาร์ม?",
      message:
          "จะมองไม่เห็นและควบคุมอุปกรณ์ของฟาร์มนี้ไม่ได้อีก (เชิญกลับมาใหม่ได้)",
      action: "ลบสมาชิก",
    );
    if (!ok || !context.mounted) return;
    await _run(
      context,
      "กำลังลบสมาชิก...",
      () => removeFarmMember(farmId, m.uid),
      "ลบสมาชิกแล้ว",
    );
  }

  Future<void> _leave(BuildContext context) async {
    final ok = await _confirm(
      context,
      title: "ออกจากฟาร์มนี้?",
      message:
          "คุณจะไม่เห็นอุปกรณ์ของฟาร์มนี้อีก ต้องให้เจ้าของเชิญใหม่ถึงจะกลับมาได้",
      action: "ออกจากฟาร์ม",
    );
    if (!ok || !context.mounted) return;
    final close = showLoadingPopup(context, "กำลังออกจากฟาร์ม...");
    try {
      await leaveFarm(farmId);
      close();
      if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on FarmApiException catch (e) {
      close();
      if (context.mounted) showErrorPopup(context, e.message);
    }
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text("ยกเลิก"),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok == true;
}

class _RoleChip extends StatelessWidget {
  final bool isOwner;
  final String? uid;
  final List<FarmMember> members;

  const _RoleChip({
    required this.isOwner,
    required this.uid,
    required this.members,
  });

  @override
  Widget build(BuildContext context) {
    final mine = members.where((m) => m.uid == uid).firstOrNull;
    final label = isOwner
        ? "คุณคือเจ้าของ"
        : mine == null
            ? "สมาชิก"
            : "สิทธิ์ของคุณ: ${levelLabel(mine.level)}";
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final FarmMember member;
  final bool isMe;
  final bool canManage;
  final ValueChanged<MemberLevel> onLevel;
  final VoidCallback onRemove;

  const _MemberTile({
    required this.member,
    required this.isMe,
    required this.canManage,
    required this.onLevel,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final name = member.name.isEmpty ? "สมาชิก" : member.name;
    return ListTile(
      leading: CircleAvatar(
        child: Text(name.characters.first.toUpperCase()),
      ),
      title: Text(isMe ? "$name (คุณ)" : name),
      subtitle: Text(levelLabel(member.level)),
      trailing: canManage
          ? PopupMenuButton<Object>(
              tooltip: "จัดการสมาชิก",
              onSelected: (v) {
                if (v is MemberLevel) {
                  onLevel(v);
                } else {
                  onRemove();
                }
              },
              itemBuilder: (_) => [
                for (final level in MemberLevel.values)
                  CheckedPopupMenuItem<Object>(
                    value: level,
                    checked: level == member.level,
                    child: Text(levelLabel(level)),
                  ),
                const PopupMenuDivider(),
                const PopupMenuItem<Object>(
                  value: 'remove',
                  child: Text("ลบออกจากฟาร์ม",
                      style: TextStyle(color: Colors.red)),
                ),
              ],
            )
          : null,
    );
  }
}

class _LevelPickerDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final MemberLevel initial;
  final String confirmLabel;

  const _LevelPickerDialog({
    required this.title,
    required this.subtitle,
    required this.initial,
    required this.confirmLabel,
  });

  @override
  State<_LevelPickerDialog> createState() => _LevelPickerDialogState();
}

class _LevelPickerDialogState extends State<_LevelPickerDialog> {
  late MemberLevel _level = widget.initial;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.subtitle,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 12),
            for (final level in MemberLevel.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _level = level),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: level == _level
                            ? scheme.primary
                            : scheme.outlineVariant,
                        width: level == _level ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          level == _level
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 20,
                          color: level == _level ? scheme.primary : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                levelLabel(level),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                levelDescription(level),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("ยกเลิก"),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _level),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _InviteCodeDialog extends StatelessWidget {
  final FarmInvite invite;
  final MemberLevel level;

  const _InviteCodeDialog({required this.invite, required this.level});

  @override
  Widget build(BuildContext context) {
    final code = invite.code;
    final pretty = "${code.substring(0, 4)} ${code.substring(4)}";
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    final e = invite.expiresAt;
    String two(int n) => n.toString().padLeft(2, '0');
    final expires =
        "${two(e.day)}/${two(e.month)}/${e.year} ${two(e.hour)}:${two(e.minute)}";

    return AlertDialog(
      title: const Text("รหัสเชิญ"),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: SelectableText(
                pretty,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "สิทธิ์ที่ผู้เข้าร่วมจะได้: ${levelLabel(level)}\n"
              "ใช้ได้ครั้งเดียว หมดอายุ $expires\n"
              "ให้เขากรอกรหัสนี้ในแอปที่หน้า \"เข้าร่วมฟาร์ม\"",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: muted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: code));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("คัดลอกรหัสแล้ว")),
              );
            }
          },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text("คัดลอก"),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("เสร็จสิ้น"),
        ),
      ],
    );
  }
}
