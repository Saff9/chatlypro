import 'package:flutter/material.dart';

/// Repeating background tile painted on chat screens with a wallpaper preset.
class ChatWallpaperPainter extends CustomPainter {
  final Color color;

  const ChatWallpaperPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.03)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    const step = 80.0;
    for (double x = 0; x < size.width; x += step) {
      for (double y = 0; y < size.height; y += step) {
        final rect = Rect.fromLTWH(x + 10, y + 10, 24, 16);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), paint);
        final path = Path()
          ..moveTo(x + 12, y + 26)
          ..lineTo(x + 8, y + 28)
          ..lineTo(x + 14, y + 26);
        canvas.drawPath(path, paint);
        canvas.drawCircle(Offset(x + 45, y + 35), 3, paint);
        canvas.drawRect(Rect.fromLTWH(x + 43, y + 35, 4, 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Decorative QR code for the Safety Numbers verification dialog.
/// Not a real scannable code — purely visual.
class MockQrCodePainter extends CustomPainter {
  const MockQrCodePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    final clear = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final sq = size.width * 0.25;

    // Top-left corner square
    canvas.drawRect(Rect.fromLTWH(0, 0, sq, sq), fill);
    canvas.drawRect(Rect.fromLTWH(sq * 0.2, sq * 0.2, sq * 0.6, sq * 0.6), clear);
    canvas.drawRect(Rect.fromLTWH(sq * 0.35, sq * 0.35, sq * 0.3, sq * 0.3), fill);

    // Top-right corner square
    canvas.drawRect(Rect.fromLTWH(size.width - sq, 0, sq, sq), fill);
    canvas.drawRect(Rect.fromLTWH(size.width - sq + sq * 0.2, sq * 0.2, sq * 0.6, sq * 0.6), clear);
    canvas.drawRect(Rect.fromLTWH(size.width - sq + sq * 0.35, sq * 0.35, sq * 0.3, sq * 0.3), fill);

    // Bottom-left corner square
    canvas.drawRect(Rect.fromLTWH(0, size.height - sq, sq, sq), fill);
    canvas.drawRect(Rect.fromLTWH(sq * 0.2, size.height - sq + sq * 0.2, sq * 0.6, sq * 0.6), clear);
    canvas.drawRect(Rect.fromLTWH(sq * 0.35, size.height - sq + sq * 0.35, sq * 0.3, sq * 0.3), fill);

    // Interior data blocks
    for (final r in [
      Rect.fromLTWH(size.width * 0.4, size.height * 0.1, 8, 8),
      Rect.fromLTWH(size.width * 0.5, size.height * 0.2, 12, 6),
      Rect.fromLTWH(size.width * 0.45, size.height * 0.35, 6, 12),
      Rect.fromLTWH(size.width * 0.6, size.height * 0.4, 8, 8),
      Rect.fromLTWH(size.width * 0.35, size.height * 0.6, 10, 10),
      Rect.fromLTWH(size.width * 0.7, size.height * 0.6, 6, 16),
      Rect.fromLTWH(size.width * 0.6, size.height * 0.75, 12, 12),
      Rect.fromLTWH(size.width * 0.75, size.height * 0.75, 8, 8),
      Rect.fromLTWH(size.width * 0.8, size.height * 0.45, 12, 8),
      Rect.fromLTWH(size.width * 0.4, size.height * 0.8, 14, 6),
    ]) {
      canvas.drawRect(r, fill);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
