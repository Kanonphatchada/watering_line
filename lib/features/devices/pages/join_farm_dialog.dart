import 'package:flutter/material.dart';
import '../services/farm_members.dart';

// กล่องกรอกรหัสเชิญเพื่อเข้าร่วมฟาร์มของคนอื่น — คืน farmId ถ้าเข้าร่วมสำเร็จ
// (ไม่สำเร็จ/ยกเลิกคืน null) แจ้ง error ในกล่องเองให้ลองกรอกใหม่ได้ทันที
Future<String?> showJoinFarmDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _JoinFarmDialog(),
  );
}

class _JoinFarmDialog extends StatefulWidget {
  const _JoinFarmDialog();

  @override
  State<_JoinFarmDialog> createState() => _JoinFarmDialogState();
}

class _JoinFarmDialogState extends State<_JoinFarmDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() => _error = "กรอกรหัสเชิญก่อน");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final farmId = await joinFarm(code);
      if (mounted) Navigator.pop(context, farmId);
    } on FarmApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("เข้าร่วมฟาร์ม"),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "กรอกรหัสเชิญ 8 ตัวที่เจ้าของฟาร์มส่งให้",
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              enabled: !_busy,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: "XXXX XXXX",
                errorText: _error,
                errorMaxLines: 3,
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: LinearProgressIndicator(),
              ),
            if (_busy)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  "อาจใช้เวลาสักครู่ถ้า server เพิ่งตื่น",
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text("ยกเลิก"),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text("เข้าร่วม"),
        ),
      ],
    );
  }
}
