import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../camera_service.dart';
import '../face_tracking_service.dart';
import '../models.dart';
import '../theme.dart';

class CoachPreview extends StatelessWidget {
  const CoachPreview({
    super.key,
    required this.cameraService,
    this.filter = 'None',
    this.recording = false,
    this.avatarStyle = const AvatarStyle(),
  });
  final CameraService cameraService;
  final String filter;
  final bool recording;
  final AvatarStyle avatarStyle;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: cameraService,
      builder: (context, _) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!cameraService.isEnabled)
              _TrackedAvatar(
                tracking: cameraService.faceTracking,
                style: avatarStyle,
              )
            else if (cameraService.isReady)
              _CoverCameraPreview(controller: cameraService.controller!)
            else if (cameraService.usesMockCamera)
              const _MockVideoPreview()
            else
              Image.asset(
                'assets/images/coach.png',
                fit: BoxFit.cover,
                alignment: const Alignment(0, -.12),
              ),
            if (cameraService.isEnabled &&
                !cameraService.usesMockCamera &&
                !cameraService.isReady &&
                cameraService.error != null)
              Positioned(
                left: 20,
                right: 20,
                top: 18,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xBB1D1B19),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    cameraService.error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            if (recording)
              const DecoratedBox(
                decoration: BoxDecoration(color: Color(0x11000000)),
              ),
            if (cameraService.isEnabled && filter != 'None')
              _FaceMappedEffect(
                tracking: cameraService.faceTracking,
                filter: filter,
              ),
          ],
        ),
      ),
    );
  }
}

class _MockVideoPreview extends StatefulWidget {
  const _MockVideoPreview();

  @override
  State<_MockVideoPreview> createState() => _MockVideoPreviewState();
}

class _MockVideoPreviewState extends State<_MockVideoPreview> {
  late final VideoPlayerController controller;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    controller = VideoPlayerController.asset('assets/mockup.mp4');
    controller
        .initialize()
        .then((_) async {
          await controller.setLooping(true);
          await controller.setVolume(0);
          await controller.play();
          if (mounted) setState(() => ready = true);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return Image.asset(
        'assets/images/coach.png',
        fit: BoxFit.cover,
        alignment: const Alignment(0, -.12),
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}

class _TrackedAvatar extends StatefulWidget {
  const _TrackedAvatar({required this.tracking, required this.style});
  final FaceTrackingService tracking;
  final AvatarStyle style;

  @override
  State<_TrackedAvatar> createState() => _TrackedAvatarState();
}

class _TrackedAvatarState extends State<_TrackedAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController ticker;
  FaceTrackingState displayed = const FaceTrackingState();
  late DateTime nextBlinkAt;
  DateTime? blinkStartedAt;

  @override
  void initState() {
    super.initState();
    ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    nextBlinkAt = DateTime.now().add(const Duration(milliseconds: 2600));
  }

  @override
  void dispose() {
    ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: ticker,
    builder: (context, _) {
      displayed = displayed.blend(widget.tracking.state, .20);
      final now = DateTime.now();
      if (blinkStartedAt == null && now.isAfter(nextBlinkAt)) {
        blinkStartedAt = now;
      }
      var blink = 0.0;
      final started = blinkStartedAt;
      if (started != null) {
        final elapsed = now.difference(started).inMilliseconds;
        blink = elapsed < 90 ? elapsed / 90 : (1 - ((elapsed - 90) / 120));
        blink = blink.clamp(0.0, 1.0);
        if (elapsed > 210) {
          blinkStartedAt = null;
          final delayMs = 2200 + (now.millisecond % 2800);
          nextBlinkAt = now.add(Duration(milliseconds: delayMs));
        }
      }
      return _PolishedCatAvatar(
        face: displayed,
        style: widget.style,
        autoBlink: blink,
      );
    },
  );
}

class _PolishedCatAvatar extends StatelessWidget {
  const _PolishedCatAvatar({
    required this.face,
    required this.style,
    this.autoBlink = 0,
  });
  final FaceTrackingState face;
  final AvatarStyle style;
  final double autoBlink;

  @override
  Widget build(BuildContext context) {
    const backgrounds = {
      'Mint': Color(0xFF67C6B4),
      'Sunshine': Color(0xFFFFC845),
      'Coral': Color(0xFFF36D58),
      'Lavender': Color(0xFF9A79A8),
    };
    const backgroundAssets = {
      'Cozy Room': 'assets/images/backgrounds/cozy-room.png',
      'Café': 'assets/images/backgrounds/cafe.png',
      'Library': 'assets/images/backgrounds/library.png',
      'Garden': 'assets/images/backgrounds/garden.png',
      'Night City': 'assets/images/backgrounds/night-city.png',
    };
    const scarfColors = {
      'Teal': Color(0xFF159B9A),
      'Berry': Color(0xFFB94B78),
      'Orange': Color(0xFFF26A2E),
      'Blue': Color(0xFF318EB2),
    };
    final background = backgrounds[style.background] ?? backgrounds['Mint']!;
    final backgroundAsset = backgroundAssets[style.background];
    final scarfColor = scarfColors[style.scarf] ?? scarfColors['Teal']!;
    return ColoredBox(
      color: background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.maxWidth;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (backgroundAsset != null)
                Image.asset(backgroundAsset, fit: BoxFit.cover),
              Positioned(
                right: -side * .12,
                top: -side * .18,
                width: side * .58,
                height: side * .58,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .10),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Center(
                child: Transform.translate(
                  offset: Offset(
                    face.yaw * side * .045,
                    face.pitch * side * .025,
                  ),
                  child: Transform.rotate(
                    angle: face.roll * .12,
                    child: SizedBox.square(
                      dimension: side,
                      child: CustomPaint(
                        painter: _SimpleCatAvatarPainter(
                          face: face,
                          style: style,
                          scarfColor: scarfColor,
                          autoBlink: autoBlink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SimpleCatAvatarPainter extends CustomPainter {
  const _SimpleCatAvatarPainter({
    required this.face,
    required this.style,
    required this.scarfColor,
    required this.autoBlink,
  });

  final FaceTrackingState face;
  final AvatarStyle style;
  final Color scarfColor;
  final double autoBlink;

  @override
  void paint(Canvas canvas, Size size) {
    const coats = {
      'White': Color(0xFFF4EBD9),
      'Ginger': Color(0xFFE78C25),
      'Gray': Color(0xFF92908F),
      'Black': Color(0xFF1C1B1E),
      'Siamese': Color(0xFF76513C),
      'Tuxedo': Color(0xFF18181A),
      'Calico': Color(0xFFF0E3CD),
      'Brown Tabby': Color(0xFFA86D31),
    };
    final coat = coats[style.cat] ?? coats['White']!;
    final patch = Color.lerp(
      coat,
      Colors.black,
      style.cat == 'White' ? .18 : .10,
    )!;
    final outline = Color.lerp(ink, coat, .08)!;
    final unit = size.shortestSide;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(unit * .20, unit * .31, unit * .60, unit * .45),
      Radius.circular(unit * .045),
    );
    final leftEar = Path()
      ..moveTo(unit * .23, unit * .34)
      ..lineTo(unit * .28, unit * .17)
      ..quadraticBezierTo(unit * .33, unit * .18, unit * .38, unit * .34)
      ..close();
    final rightEar = Path()
      ..moveTo(unit * .62, unit * .34)
      ..quadraticBezierTo(unit * .67, unit * .18, unit * .72, unit * .17)
      ..lineTo(unit * .77, unit * .34)
      ..close();
    final paint = Paint()
      ..isAntiAlias = false
      ..strokeJoin = StrokeJoin.round;
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: .10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawRRect(body.shift(Offset(unit * .016, unit * .020)), shadow);
    paint.color = coat;
    canvas.drawPath(leftEar, paint);
    canvas.drawPath(rightEar, paint);
    canvas.drawRRect(body, paint);

    _drawPatch(canvas, unit, patch, coat);
    _drawEarInner(canvas, unit);
    _drawTail(canvas, unit, coat, outline);
    _drawLegs(canvas, unit, coat, outline);
    _drawOutline(canvas, body, leftEar, rightEar, outline, unit);
    _drawFace(canvas, unit, outline);
    _drawScarf(canvas, unit, scarfColor, outline);
  }

  void _drawPatch(Canvas canvas, double unit, Color patch, Color coat) {
    final path = Path()
      ..moveTo(unit * .27, unit * .31)
      ..quadraticBezierTo(unit * .37, unit * .34, unit * .43, unit * .45)
      ..quadraticBezierTo(unit * .50, unit * .58, unit * .57, unit * .45)
      ..quadraticBezierTo(unit * .63, unit * .34, unit * .73, unit * .31)
      ..lineTo(unit * .73, unit * .31)
      ..lineTo(unit * .27, unit * .31)
      ..close();
    canvas.drawPath(path, Paint()..color = patch.withValues(alpha: .55));
    if (style.cat == 'Tuxedo') {
      canvas.drawPath(
        Path()
          ..moveTo(unit * .20, unit * .31)
          ..lineTo(unit * .42, unit * .31)
          ..lineTo(unit * .50, unit * .48)
          ..lineTo(unit * .58, unit * .31)
          ..lineTo(unit * .80, unit * .31)
          ..lineTo(unit * .80, unit * .76)
          ..lineTo(unit * .20, unit * .76)
          ..close(),
        Paint()..color = coat,
      );
    }
  }

  void _drawEarInner(Canvas canvas, double unit) {
    final paint = Paint()..color = const Color(0xFFFFE7DF);
    canvas.drawPath(
      Path()
        ..moveTo(unit * .275, unit * .31)
        ..lineTo(unit * .30, unit * .225)
        ..lineTo(unit * .345, unit * .31)
        ..close(),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(unit * .655, unit * .31)
        ..lineTo(unit * .70, unit * .225)
        ..lineTo(unit * .725, unit * .31)
        ..close(),
      paint,
    );
  }

  void _drawTail(Canvas canvas, double unit, Color coat, Color outline) {
    final stroke = Paint()
      ..color = coat
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * .045
      ..strokeCap = StrokeCap.round;
    final outlineStroke = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * .065
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(unit * .79, unit * .61)
      ..cubicTo(
        unit * .93,
        unit * .62,
        unit * .92,
        unit * .50,
        unit * .90,
        unit * .49,
      );
    canvas.drawPath(path, outlineStroke);
    canvas.drawPath(path, stroke);
  }

  void _drawLegs(Canvas canvas, double unit, Color coat, Color outline) {
    final paint = Paint()..color = coat;
    final stroke = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * .012;
    for (final x in [.30, .70]) {
      final foot = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(unit * x, unit * .765),
          width: unit * .07,
          height: unit * .045,
        ),
        Radius.circular(unit * .014),
      );
      canvas.drawRRect(foot, paint);
      canvas.drawRRect(foot, stroke);
    }
  }

  void _drawOutline(
    Canvas canvas,
    RRect body,
    Path leftEar,
    Path rightEar,
    Color outline,
    double unit,
  ) {
    final stroke = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * .014
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(leftEar, stroke);
    canvas.drawPath(rightEar, stroke);
    canvas.drawRRect(body, stroke);
  }

  void _drawFace(Canvas canvas, double unit, Color outline) {
    final blinkAmount = math
        .max(autoBlink, math.max(1 - face.leftEye, 1 - face.rightEye))
        .clamp(0.0, 1.0);
    final tired = face.pitch > .32;
    final leftEye = Offset(unit * .39, unit * .485);
    final rightEye = Offset(unit * .61, unit * .485);
    _drawEye(canvas, unit, leftEye, blinkAmount, tired);
    _drawEye(canvas, unit, rightEye, blinkAmount, tired);

    final line = Paint()
      ..color = outline
      ..strokeWidth = unit * .012
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(unit * .30, unit * .53),
      Offset(unit * .24, unit * .525),
      line,
    );
    canvas.drawLine(
      Offset(unit * .30, unit * .56),
      Offset(unit * .24, unit * .565),
      line,
    );
    canvas.drawLine(
      Offset(unit * .70, unit * .53),
      Offset(unit * .76, unit * .525),
      line,
    );
    canvas.drawLine(
      Offset(unit * .70, unit * .56),
      Offset(unit * .76, unit * .565),
      line,
    );

    canvas.drawCircle(
      Offset(unit * .50, unit * .555),
      unit * .010,
      Paint()..color = outline,
    );
    _drawMouth(canvas, unit, outline);
  }

  void _drawEye(
    Canvas canvas,
    double unit,
    Offset center,
    double blinkAmount,
    bool tired,
  ) {
    final blink = blinkAmount.clamp(0.0, 1.0);
    if (blink > .72 || tired) {
      final y = center.dy + (tired ? unit * .015 : 0);
      canvas.drawLine(
        Offset(center.dx - unit * .030, y),
        Offset(center.dx + unit * .030, y - (tired ? unit * .008 : 0)),
        Paint()
          ..color = ink
          ..strokeWidth = unit * .014
          ..strokeCap = StrokeCap.round,
      );
      return;
    }
    final eyeRect = Rect.fromCenter(
      center: center,
      width: unit * .043,
      height: unit * (.080 * (1 - blink * .55)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(eyeRect, Radius.circular(unit * .010)),
      Paint()..color = ink,
    );
    canvas.drawCircle(
      Offset(center.dx - unit * .007, eyeRect.top + unit * .017),
      unit * .006,
      Paint()..color = Colors.white,
    );
  }

  void _drawMouth(Canvas canvas, double unit, Color outline) {
    final open = face.mouthOpen.clamp(0.0, 1.0);
    if (face.smile > .72 && open < .32) {
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(unit * .50, unit * .565),
          width: unit * .090,
          height: unit * .070,
        ),
        0,
        math.pi,
        false,
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = unit * .012
          ..strokeCap = StrokeCap.round,
      );
      return;
    }
    if (open < .18) {
      final path = Path()
        ..moveTo(unit * .475, unit * .575)
        ..quadraticBezierTo(unit * .50, unit * .588, unit * .525, unit * .575);
      canvas.drawPath(
        path,
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = unit * .010
          ..strokeCap = StrokeCap.round,
      );
      return;
    }
    final mouthState = open < .38
        ? 1
        : open < .68
        ? 2
        : 3;
    final mouthSizes = {
      1: Size(unit * .055, unit * .052),
      2: Size(unit * .095, unit * .090),
      3: Size(unit * .135, unit * .145),
    };
    final mouthSize = mouthSizes[mouthState]!;
    final rect = Rect.fromCenter(
      center: Offset(unit * .50, unit * .585),
      width: mouthSize.width,
      height: mouthSize.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(unit * .008)),
      Paint()..color = outline,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(unit * .008),
        Radius.circular(unit * .006),
      ),
      Paint()..color = const Color(0xFFF09A9C),
    );
  }

  void _drawScarf(Canvas canvas, double unit, Color color, Color outline) {
    final paint = Paint()
      ..color = color
      ..isAntiAlias = false;
    final neck = Rect.fromCenter(
      center: Offset(unit * .50, unit * .765),
      width: unit * .44,
      height: unit * .060,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(neck, Radius.circular(unit * .014)),
      paint,
    );
    paint.color = Color.lerp(color, Colors.black, .12)!;
    canvas.drawPath(
      Path()
        ..moveTo(unit * .49, unit * .785)
        ..lineTo(unit * .59, unit * .895)
        ..quadraticBezierTo(unit * .54, unit * .915, unit * .47, unit * .795)
        ..close(),
      paint,
    );
    final stroke = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * .010;
    canvas.drawRRect(
      RRect.fromRectAndRadius(neck, Radius.circular(unit * .014)),
      stroke,
    );
    canvas.drawLine(
      Offset(neck.left + unit * .04, neck.center.dy),
      Offset(neck.right - unit * .04, neck.center.dy),
      Paint()
        ..color = Colors.white.withValues(alpha: .28)
        ..strokeWidth = unit * .010
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SimpleCatAvatarPainter oldDelegate) =>
      oldDelegate.face != face ||
      oldDelegate.style != style ||
      oldDelegate.autoBlink != autoBlink;
}

class _FaceMappedEffect extends StatelessWidget {
  const _FaceMappedEffect({required this.tracking, required this.filter});

  final FaceTrackingService tracking;
  final String filter;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: tracking,
    builder: (context, _) {
      final face = tracking.state;
      if (!face.faceDetected) return const SizedBox.shrink();
      return LayoutBuilder(
        builder: (context, constraints) {
          final x = face.faceCenterX * constraints.maxWidth;
          final y = face.faceCenterY * constraints.maxHeight;
          final w = face.faceWidth * constraints.maxWidth;
          final h = face.faceHeight * constraints.maxHeight;
          return CustomPaint(
            painter: _FaceEffectPainter(
              filter: filter,
              center: Offset(x, y),
              faceSize: Size(w, h),
              roll: face.roll,
              smile: face.smile,
            ),
            size: Size.infinite,
          );
        },
      );
    },
  );
}

class _FaceEffectPainter extends CustomPainter {
  const _FaceEffectPainter({
    required this.filter,
    required this.center,
    required this.faceSize,
    required this.roll,
    required this.smile,
  });

  final String filter;
  final Offset center;
  final Size faceSize;
  final double roll;
  final double smile;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(roll * .2);
    final paint = Paint()..isAntiAlias = true;
    final width = faceSize.width.clamp(70.0, size.width * .82);
    if (filter == 'Glasses' || filter == 'Funny') {
      _glasses(canvas, width, filter == 'Funny');
    } else if (filter == 'Hat') {
      _hat(canvas, width);
    } else if (filter == 'Cat') {
      _catEars(canvas, width);
    }
    canvas.restore();
    paint.color = Colors.white.withValues(alpha: .72);
    canvas.drawCircle(
      Offset(center.dx - width * .52, center.dy - faceSize.height * .42),
      4,
      paint,
    );
    canvas.drawCircle(
      Offset(center.dx + width * .46, center.dy - faceSize.height * .23),
      3,
      paint,
    );
  }

  void _glasses(Canvas canvas, double width, bool funny) {
    final stroke = Paint()
      ..color = funny ? const Color(0xFFFFD84D) : Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * .055
      ..strokeCap = StrokeCap.round;
    final y = -width * .04;
    final left = Rect.fromCenter(
      center: Offset(-width * .18, y),
      width: width * .27,
      height: width * .20,
    );
    final right = Rect.fromCenter(
      center: Offset(width * .18, y),
      width: width * .27,
      height: width * .20,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(left, Radius.circular(width * .05)),
      stroke,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(right, Radius.circular(width * .05)),
      stroke,
    );
    canvas.drawLine(Offset(left.right, y), Offset(right.left, y), stroke);
    if (funny) {
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(0, width * .22),
          width: width * (.18 + smile * .06),
          height: width * .10,
        ),
        0,
        3.14,
        false,
        stroke,
      );
    }
  }

  void _hat(Canvas canvas, double width) {
    final paint = Paint()..color = const Color(0xFF22211F);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, -width * .55),
          width: width * .62,
          height: width * .16,
        ),
        Radius.circular(width * .04),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, -width * .70),
          width: width * .40,
          height: width * .25,
        ),
        Radius.circular(width * .06),
      ),
      paint,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(0, -width * .63),
        width: width * .38,
        height: width * .045,
      ),
      Paint()..color = yellow,
    );
  }

  void _catEars(Canvas canvas, double width) {
    final paint = Paint()..color = const Color(0xFFF2C9A2);
    for (final side in [-1, 1]) {
      final path = Path()
        ..moveTo(side * width * .18, -width * .45)
        ..lineTo(side * width * .34, -width * .76)
        ..lineTo(side * width * .47, -width * .39)
        ..close();
      canvas.drawPath(path, paint);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black.withValues(alpha: .12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * .025,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FaceEffectPainter oldDelegate) =>
      oldDelegate.filter != filter ||
      oldDelegate.center != center ||
      oldDelegate.faceSize != faceSize ||
      oldDelegate.roll != roll ||
      oldDelegate.smile != smile;
}

class _CoverCameraPreview extends StatelessWidget {
  const _CoverCameraPreview({required this.controller});
  final CameraController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = controller.value.previewSize;
      if (size == null) return const SizedBox.shrink();
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.height,
            height: size.width,
            child: CameraPreview(controller),
          ),
        ),
      );
    },
  );
}

class TopicCard extends StatefulWidget {
  const TopicCard({super.key, required this.topic, required this.onRandom});
  final String topic;
  final Future<void> Function() onRandom;

  @override
  State<TopicCard> createState() => _TopicCardState();
}

class _TopicCardState extends State<TopicCard> {
  int spins = 0;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 18),
    padding: const EdgeInsets.fromLTRB(20, 15, 12, 8),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFCF3),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: ink, width: 1.8),
      boxShadow: const [
        BoxShadow(color: Color(0x25000000), offset: Offset(3, 4)),
      ],
    ),
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: -32,
          left: 70,
          right: 70,
          child: Transform.rotate(
            angle: -.04,
            child: Container(height: 24, color: const Color(0xBBDDBA75)),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'TOPIC',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 330),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween(begin: .94, end: 1.0).animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                widget.topic,
                key: ValueKey(widget.topic),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(height: 1.13),
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: TweenAnimationBuilder<double>(
                key: ValueKey(spins),
                tween: Tween(begin: 0, end: spins == 0 ? 0 : 1),
                duration: const Duration(milliseconds: 520),
                curve: Curves.easeOutBack,
                builder: (_, turn, child) =>
                    Transform.rotate(angle: turn * 6.283, child: child),
                child: InkWell(
                  onTap: () async {
                    setState(() => spins++);
                    await widget.onRandom();
                  },
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: yellow,
                      shape: BoxShape.circle,
                      border: Border.all(color: ink, width: 1.7),
                      boxShadow: const [
                        BoxShadow(color: ink, offset: Offset(2, 2)),
                      ],
                    ),
                    child: const Icon(Icons.casino_outlined, size: 23),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class ChoiceChipRow extends StatelessWidget {
  const ChoiceChipRow({
    super.key,
    required this.values,
    required this.selected,
    required this.onSelected,
  });
  final List<String> values;
  final String selected;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: values
        .map(
          (value) => ChoiceChip(
            label: Text(value, style: const TextStyle(fontSize: 12)),
            selected: selected == value,
            selectedColor: purpleSoft,
            side: BorderSide(
              color: selected == value ? purple : const Color(0xFFD8D0C4),
            ),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => onSelected(value),
          ),
        )
        .toList(),
  );
}

class AvatarCustomizer extends StatefulWidget {
  const AvatarCustomizer({super.key, required this.initial});
  final AvatarStyle initial;

  @override
  State<AvatarCustomizer> createState() => _AvatarCustomizerState();
}

class _AvatarCustomizerState extends State<AvatarCustomizer> {
  late AvatarStyle style = widget.initial;

  @override
  Widget build(BuildContext context) => BottomSheetShell(
    title: 'Customize Your Cat',
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .72,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 148,
                height: 148,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: ink, width: 1.6),
                  boxShadow: const [
                    BoxShadow(color: Color(0x24000000), offset: Offset(3, 4)),
                  ],
                ),
                child: _PolishedCatAvatar(
                  face: const FaceTrackingState(smile: .25),
                  style: style,
                ),
              ),
            ),
            const SizedBox(height: 14),
            _option(
              'CAT',
              [
                'White',
                'Ginger',
                'Gray',
                'Black',
                'Siamese',
                'Tuxedo',
                'Calico',
                'Brown Tabby',
              ],
              style.cat,
              (value) => style = style.copyWith(cat: value),
            ),
            _option(
              'SCARF',
              ['Teal', 'Berry', 'Orange', 'Blue'],
              style.scarf,
              (value) => style = style.copyWith(scarf: value),
            ),
            _option(
              'BACKGROUND',
              [
                'Mint',
                'Sunshine',
                'Coral',
                'Lavender',
                'Cozy Room',
                'Café',
                'Library',
                'Garden',
                'Night City',
              ],
              style.background,
              (value) => style = style.copyWith(background: value),
            ),
            const SizedBox(height: 8),
            PurpleButton(
              label: 'APPLY CAT',
              onPressed: () => Navigator.pop(context, style),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _option(
    String label,
    List<String> values,
    String selected,
    ValueChanged<String> update,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        ChoiceChipRow(
          values: values,
          selected: selected,
          onSelected: (value) => setState(() => update(value)),
        ),
      ],
    ),
  );
}

class BottomSheetShell extends StatelessWidget {
  const BottomSheetShell({super.key, required this.child, this.title});
  final Widget child;
  final String? title;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: const BoxDecoration(
      color: paper,
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFB8B0A6),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            if (title != null) ...[
              const SizedBox(height: 10),
              Text(title!, style: Theme.of(context).textTheme.titleMedium),
            ],
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    ),
  );
}
