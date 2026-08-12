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

  @override
  void initState() {
    super.initState();
    ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
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
      return _PolishedCatAvatar(face: displayed, style: widget.style);
    },
  );
}

class _PolishedCatAvatar extends StatelessWidget {
  const _PolishedCatAvatar({required this.face, required this.style});
  final FaceTrackingState face;
  final AvatarStyle style;

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
  });

  final FaceTrackingState face;
  final AvatarStyle style;
  final Color scarfColor;

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
    final shade = Color.lerp(coat, Colors.black, .12)!;
    final blush = const Color(
      0xFFFFA9A9,
    ).withValues(alpha: .28 + face.smile * .18);
    final cx = size.width * .5;
    final cy = size.height * .48;
    final head = Rect.fromCenter(
      center: Offset(cx, cy),
      width: size.width * .58,
      height: size.height * .50,
    );
    final headPath = Path()..addOval(head);
    final leftEar = Path()
      ..moveTo(size.width * .24, size.height * .35)
      ..quadraticBezierTo(
        size.width * .25,
        size.height * .12,
        size.width * .40,
        size.height * .28,
      )
      ..close();
    final rightEar = Path()
      ..moveTo(size.width * .60, size.height * .28)
      ..quadraticBezierTo(
        size.width * .75,
        size.height * .12,
        size.width * .76,
        size.height * .35,
      )
      ..close();
    final paint = Paint()..isAntiAlias = true;
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: .12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13);
    canvas.drawOval(head.shift(Offset(0, size.height * .035)), shadow);
    paint.color = coat;
    canvas.drawPath(leftEar, paint);
    canvas.drawPath(rightEar, paint);
    canvas.drawPath(headPath, paint);

    paint.color = Color.lerp(coat, Colors.white, .35)!;
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .285, size.height * .30)
        ..quadraticBezierTo(
          size.width * .285,
          size.height * .20,
          size.width * .36,
          size.height * .285,
        )
        ..close(),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .64, size.height * .285)
        ..quadraticBezierTo(
          size.width * .715,
          size.height * .20,
          size.width * .715,
          size.height * .30,
        )
        ..close(),
      paint,
    );

    final eyeY = size.height * (.435 + face.pitch * .014);
    _drawEye(canvas, size, Offset(size.width * .39, eyeY), face.leftEye);
    _drawEye(canvas, size, Offset(size.width * .61, eyeY), face.rightEye);

    paint.color = blush;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * .34, size.height * .545),
        width: size.width * .09,
        height: size.height * .04,
      ),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * .66, size.height * .545),
        width: size.width * .09,
        height: size.height * .04,
      ),
      paint,
    );

    paint.color = shade;
    canvas.drawCircle(
      Offset(size.width * .5, size.height * .535),
      size.width * .018,
      paint,
    );
    final mouthOpen = face.mouthOpen.clamp(0.0, 1.0);
    final smile = face.smile.clamp(0.0, 1.0);
    final mouthRect = Rect.fromCenter(
      center: Offset(size.width * .5, size.height * .585),
      width: size.width * (.07 + smile * .035),
      height: size.height * (.012 + mouthOpen * .065),
    );
    paint.color = const Color(0xFF3A2023);
    if (mouthOpen > .22) {
      canvas.drawOval(mouthRect, paint);
      paint.color = const Color(0xFFFF7D8E).withValues(alpha: .78);
      canvas.drawOval(
        mouthRect
            .deflate(size.width * .018)
            .shift(Offset(0, size.height * .014)),
        paint,
      );
    } else {
      final path = Path()
        ..moveTo(size.width * .46, size.height * .575)
        ..quadraticBezierTo(
          size.width * .5,
          size.height * (.598 + smile * .012),
          size.width * .54,
          size.height * .575,
        );
      canvas.drawPath(
        path,
        Paint()
          ..color = shade
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * .009
          ..strokeCap = StrokeCap.round,
      );
    }

    _drawWhiskers(canvas, size, shade.withValues(alpha: .72));
    _drawScarf(canvas, size, scarfColor);
  }

  void _drawEye(Canvas canvas, Size size, Offset center, double openness) {
    final eyeRect = Rect.fromCenter(
      center: center,
      width: size.width * .105,
      height: size.height * .106,
    );
    final open = openness.clamp(0.0, 1.0);
    if (open < .18) {
      canvas.drawLine(
        Offset(eyeRect.left + size.width * .016, center.dy),
        Offset(eyeRect.right - size.width * .016, center.dy),
        Paint()
          ..color = ink
          ..strokeWidth = size.width * .012
          ..strokeCap = StrokeCap.round,
      );
      return;
    }
    canvas.drawOval(eyeRect, Paint()..color = Colors.white);
    canvas.drawOval(eyeRect.deflate(size.width * .025), Paint()..color = ink);
    canvas.drawCircle(
      Offset(center.dx - size.width * .014, center.dy - size.height * .018),
      size.width * .012,
      Paint()..color = Colors.white,
    );
    final cover = (1 - open) * eyeRect.height * .82;
    canvas.drawRect(
      Rect.fromLTWH(eyeRect.left, eyeRect.top, eyeRect.width, cover),
      Paint()..color = const Color(0xFF2E2420).withValues(alpha: .18),
    );
  }

  void _drawWhiskers(Canvas canvas, Size size, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * .006
      ..strokeCap = StrokeCap.round;
    for (final y in [.55, .585]) {
      canvas.drawLine(
        Offset(size.width * .23, size.height * y),
        Offset(size.width * .40, size.height * (y - .015)),
        paint,
      );
      canvas.drawLine(
        Offset(size.width * .60, size.height * (y - .015)),
        Offset(size.width * .77, size.height * y),
        paint,
      );
    }
  }

  void _drawScarf(Canvas canvas, Size size, Color color) {
    final paint = Paint()..color = color;
    final neck = Rect.fromCenter(
      center: Offset(size.width * .5, size.height * .735),
      width: size.width * .42,
      height: size.height * .11,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(neck, Radius.circular(size.width * .04)),
      paint,
    );
    paint.color = Color.lerp(color, Colors.black, .12)!;
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .48, size.height * .755)
        ..lineTo(size.width * .61, size.height * .89)
        ..quadraticBezierTo(
          size.width * .55,
          size.height * .91,
          size.width * .47,
          size.height * .79,
        )
        ..close(),
      paint,
    );
    paint.color = Colors.white.withValues(alpha: .28);
    canvas.drawLine(
      Offset(neck.left + size.width * .05, neck.center.dy),
      Offset(neck.right - size.width * .05, neck.center.dy),
      Paint()
        ..color = Colors.white.withValues(alpha: .28)
        ..strokeWidth = size.width * .012
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SimpleCatAvatarPainter oldDelegate) =>
      oldDelegate.face != face || oldDelegate.style != style;
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
