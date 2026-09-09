import 'package:flutter/material.dart';

/// Circular profile picture. Uses [Alignment.topCenter] instead of the
/// default center crop — most profile photos have the face near the top,
/// and a plain center-crop on a non-square source image (common with LINE
/// profile pictures) can end up hiding the face entirely.
class Avatar extends StatelessWidget {
  final String? photoUrl;
  final double size;

  const Avatar({super.key, required this.photoUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url == null
            ? _fallbackIcon(context)
            : Image.network(
                url,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (context, error, stackTrace) =>
                    _fallbackIcon(context),
              ),
      ),
    );
  }

  Widget _fallbackIcon(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(Icons.person, size: size * 0.55),
    );
  }
}
