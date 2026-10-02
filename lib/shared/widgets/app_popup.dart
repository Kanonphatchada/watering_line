import 'dart:async';
import 'package:flutter/material.dart';

// ป็อปอัพแจ้งผลกลางจอ ใช้แทน SnackBar ที่โผล่ขอบล่างจอ (ผู้ใช้มองไม่ค่อยเห็น
// และไม่รู้สึกว่า "ยืนยัน" แล้ว) — เด้งขึ้นมาแบบขยายนุ่มๆ
//  - success: ปิดเองใน ~1.6 วิ (แตะที่ไหนก็ปิดได้เลย)
//  - error/info: ค้างไว้จนกด "ตกลง" จะได้อ่านทันว่าเกิดอะไรขึ้น
enum PopupKind { success, error, info }

Future<void> showAppPopup(
  BuildContext context,
  String message, {
  PopupKind kind = PopupKind.success,
  String? title,
}) {
  final (IconData icon, Color color, String defaultTitle) = switch (kind) {
    PopupKind.success => (
        Icons.check_rounded,
        const Color(0xFF2E7D32),
        "สำเร็จ",
      ),
    PopupKind.error => (
        Icons.priority_high_rounded,
        const Color(0xFFD32F2F),
        "ไม่สำเร็จ",
      ),
    PopupKind.info => (
        Icons.info_outline_rounded,
        const Color(0xFF1E88E5),
        "แจ้งให้ทราบ",
      ),
  };
  final autoClose = kind == PopupKind.success;
  Timer? timer;

  final future = showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: "ปิด",
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (dialogContext, _, __) {
      if (autoClose) {
        timer = Timer(const Duration(milliseconds: 1600), () {
          // ปิดเฉพาะถ้าป็อปอัพนี้ยังเป็นหน้าบนสุดอยู่ กันไป pop หน้าอื่นผิดตัว
          // ในกรณีที่ผู้ใช้แตะปิดเองไปก่อนแล้ว
          final route = ModalRoute.of(dialogContext);
          if (route != null && route.isCurrent) {
            Navigator.of(dialogContext).pop();
          }
        });
      }
      return _PopupCard(
        icon: icon,
        color: color,
        title: title ?? defaultTitle,
        message: message,
        showButton: !autoClose,
      );
    },
    transitionBuilder: (_, anim, __, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween(begin: 0.85, end: 1.0).animate(
          CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
        ),
        child: child,
      ),
    ),
  );
  return future.whenComplete(() => timer?.cancel());
}

Future<void> showSuccessPopup(BuildContext context, String message) =>
    showAppPopup(context, message);

Future<void> showErrorPopup(BuildContext context, String message) =>
    showAppPopup(context, message, kind: PopupKind.error);

// ป็อปอัพ "กำลังทำงาน..." กลางจอ ปิดด้วยการแตะไม่ได้ — คืนฟังก์ชันไว้เรียก
// ปิดเมื่องานเสร็จ ใช้กับงานที่อาจนาน เช่น เรียก backend ตอน Render เพิ่งตื่น
VoidCallback showLoadingPopup(BuildContext context, String message) {
  BuildContext? dialogContext;
  var closed = false;

  showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, __) {
      dialogContext = ctx;
      return PopScope(
        canPop: false,
        child: _PopupCard(
          icon: null,
          color: Theme.of(ctx).colorScheme.primary,
          title: null,
          message: message,
          showButton: false,
        ),
      );
    },
    transitionBuilder: (_, anim, __, child) =>
        FadeTransition(opacity: anim, child: child),
  );

  return () {
    if (closed) return;
    closed = true;
    final ctx = dialogContext;
    if (ctx != null && ctx.mounted) Navigator.of(ctx).pop();
  };
}

class _PopupCard extends StatelessWidget {
  final IconData? icon; // null = วงหมุน loading
  final Color color;
  final String? title;
  final String message;
  final bool showButton;

  const _PopupCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    required this.showButton,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Material(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
            elevation: 12,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.15),
                    ),
                    child: icon == null
                        ? Padding(
                            padding: const EdgeInsets.all(18),
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: color,
                            ),
                          )
                        : Icon(icon, size: 36, color: color),
                  ),
                  const SizedBox(height: 16),
                  if (title != null) ...[
                    Text(
                      title!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                  if (showButton) ...[
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text("ตกลง"),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
