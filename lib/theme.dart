import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const paper = Color(0xFFFAF9F3);
const paperDeep = Color(0xFFF1EFE4);
const gridLine = Color(0xFFDDDCD5);
const ink = Color(0xFF171717);
const inkSoft = Color(0xFF4A4A46);
const yellow = Color(0xFFFFD84D);
const yellowDeep = Color(0xFFE9B93A);
const purple = Color(0xFF3F8CFF);
const purpleSoft = Color(0xFFE4EEFF);
const green = Color(0xFF39C982);
const orange = Color(0xFFF5A623);

ThemeData buildSpeakUpTheme() {
  final body = GoogleFonts.patrickHand(color: ink);
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: Colors.transparent,
    colorScheme: const ColorScheme.light(
      primary: yellow,
      onPrimary: ink,
      secondary: purple,
      surface: paper,
      onSurface: ink,
      error: Color(0xFFEF5C5C),
    ),
    textTheme: TextTheme(
      headlineLarge: GoogleFonts.kalam(
        fontSize: 48,
        height: 1,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      headlineMedium: GoogleFonts.kalam(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      titleLarge: GoogleFonts.patrickHand(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      titleMedium: GoogleFonts.patrickHand(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyLarge: body.copyWith(fontSize: 18, height: 1.35),
      bodyMedium: body.copyWith(fontSize: 16, height: 1.3, color: inkSoft),
      labelLarge: GoogleFonts.patrickHand(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: paper,
      selectedColor: yellow,
      labelStyle: GoogleFonts.patrickHand(fontSize: 14, color: ink),
      side: const BorderSide(color: ink, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

class PaperBackground extends StatelessWidget {
  const PaperBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: const _NotebookPainter(),
    child: SizedBox.expand(child: child),
  );
}

class _NotebookPainter extends CustomPainter {
  const _NotebookPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = paper);
    final paint = Paint()
      ..color = gridLine.withValues(alpha: .62)
      ..strokeWidth = .7;
    const gap = 26.0;
    for (double x = 0; x <= size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class PurpleButton extends StatelessWidget {
  const PurpleButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: FilledButton.icon(
      onPressed: onPressed,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 20),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: yellow,
        foregroundColor: ink,
        side: const BorderSide(color: ink, width: 2.2),
        elevation: 4,
        shadowColor: ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
    ),
  );
}
