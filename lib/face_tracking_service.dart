import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class FaceTrackingState {
  const FaceTrackingState({
    this.yaw = 0,
    this.pitch = 0,
    this.roll = 0,
    this.leftEye = 1,
    this.rightEye = 1,
    this.mouthOpen = 0,
    this.smile = 0,
    this.faceDetected = false,
    this.faceCenterX = .5,
    this.faceCenterY = .5,
    this.faceWidth = .45,
    this.faceHeight = .55,
  });

  final double yaw, pitch, roll, leftEye, rightEye, mouthOpen, smile;
  final bool faceDetected;
  final double faceCenterX, faceCenterY, faceWidth, faceHeight;

  FaceTrackingState blend(FaceTrackingState next, double amount) =>
      FaceTrackingState(
        yaw: _lerp(yaw, next.yaw, amount),
        pitch: _lerp(pitch, next.pitch, amount),
        roll: _lerp(roll, next.roll, amount),
        leftEye: _lerp(leftEye, next.leftEye, amount),
        rightEye: _lerp(rightEye, next.rightEye, amount),
        mouthOpen: _lerp(mouthOpen, next.mouthOpen, amount),
        smile: _lerp(smile, next.smile, amount),
        faceDetected: next.faceDetected,
        faceCenterX: _lerp(faceCenterX, next.faceCenterX, amount),
        faceCenterY: _lerp(faceCenterY, next.faceCenterY, amount),
        faceWidth: _lerp(faceWidth, next.faceWidth, amount),
        faceHeight: _lerp(faceHeight, next.faceHeight, amount),
      );

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

class FaceTrackingService extends ChangeNotifier {
  static const _channel = MethodChannel('com.speakup.app/face_tracking');

  FaceTrackingState state = const FaceTrackingState();
  bool _processing = false;
  bool _streaming = false;
  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _mockTimer;
  CameraController? _controller;

  Future<void> start(CameraController? controller) async {
    await stop();
    _controller = controller;
    if (controller == null || !controller.value.isInitialized) {
      _startMockMotion();
      return;
    }
    try {
      await controller.startImageStream(_processFrame);
      _streaming = true;
    } on CameraException {
      _startMockMotion();
    }
  }

  Future<void> prepareForVideoFrames(CameraController controller) async {
    await stop();
    _controller = controller;
  }

  Future<void> processVideoFrame(CameraImage image) => _processFrame(image);

  Future<void> stop() async {
    _mockTimer?.cancel();
    _mockTimer = null;
    final controller = _controller;
    _controller = null;
    if (_streaming && controller?.value.isStreamingImages == true) {
      try {
        await controller!.stopImageStream();
      } on CameraException {
        // Camera may already be closing during a lifecycle transition.
      }
    }
    _streaming = false;
    _processing = false;
  }

  void _startMockMotion() {
    final started = DateTime.now();
    _mockTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final t = DateTime.now().difference(started).inMilliseconds / 1000;
      final blinkPhase = t % 3.1;
      final eye = blinkPhase > 2.88
          ? ((blinkPhase - 2.88) / .11 - 1).abs()
          : 1.0;
      state = FaceTrackingState(
        yaw: math.sin(t * .72) * .32,
        pitch: math.sin(t * .53) * .13,
        roll: math.sin(t * .41) * .10,
        leftEye: eye.clamp(0, 1),
        rightEye: eye.clamp(0, 1),
        mouthOpen: (.22 + math.sin(t * 5.1) * .18).clamp(0, 1),
        smile: (.48 + math.sin(t * .8) * .22).clamp(0, 1),
        faceDetected: true,
        faceCenterX: .5 + math.sin(t * .72) * .05,
        faceCenterY: .48 + math.sin(t * .53) * .025,
        faceWidth: .42,
        faceHeight: .52,
      );
      notifyListeners();
    });
  }

  Future<void> _processFrame(CameraImage image) async {
    final now = DateTime.now();
    if (_processing || now.difference(_lastProcessed).inMilliseconds < 66) {
      return;
    }
    _processing = true;
    _lastProcessed = now;
    try {
      if ((!Platform.isIOS && !Platform.isAndroid) ||
          image.planes.length != 1) {
        return;
      }
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'processFrame',
        {
          'bytes': image.planes.first.bytes,
          'width': image.width,
          'height': image.height,
          'bytesPerRow': image.planes.first.bytesPerRow,
          'sensorOrientation': _controller?.description.sensorOrientation ?? 90,
          'frontCamera':
              _controller?.description.lensDirection ==
              CameraLensDirection.front,
        },
      );
      if (result == null || result['detected'] != true) {
        state = state.blend(const FaceTrackingState(), .18);
        notifyListeners();
        return;
      }
      final next = FaceTrackingState(
        yaw: _number(result['yaw'], 0).clamp(-1, 1),
        pitch: _number(result['pitch'], 0).clamp(-1, 1),
        roll: _number(result['roll'], 0).clamp(-1, 1),
        leftEye: _number(result['leftEye'], 1).clamp(0, 1),
        rightEye: _number(result['rightEye'], 1).clamp(0, 1),
        mouthOpen: _number(result['mouthOpen'], 0).clamp(0, 1),
        smile: _number(result['smile'], 0).clamp(0, 1),
        faceDetected: true,
        faceCenterX: _number(result['faceCenterX'], .5).clamp(0, 1),
        faceCenterY: _number(result['faceCenterY'], .5).clamp(0, 1),
        faceWidth: _number(result['faceWidth'], .45).clamp(.05, 1),
        faceHeight: _number(result['faceHeight'], .55).clamp(.05, 1),
      );
      state = state.blend(next, .38);
      notifyListeners();
    } on PlatformException {
      _startMockMotion();
    } finally {
      _processing = false;
    }
  }

  static double _number(dynamic value, double fallback) =>
      value is num ? value.toDouble() : fallback;

  @override
  void dispose() {
    _mockTimer?.cancel();
    super.dispose();
  }
}
