import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import 'face_tracking_service.dart';

class CameraService extends ChangeNotifier {
  CameraService(this.cameras);
  CameraService.disabled() : cameras = const [];

  final List<CameraDescription> cameras;
  CameraController? controller;
  String? error;
  int _index = 0;
  bool _initializing = false;
  bool isEnabled = true;
  final FaceTrackingService faceTracking = FaceTrackingService();

  bool get isReady => controller?.value.isInitialized ?? false;
  bool get canFlip => cameras.length > 1;
  bool get usesMockCamera => cameras.isEmpty;

  Future<void> initialize({
    CameraLensDirection preferred = CameraLensDirection.front,
  }) async {
    if (_initializing || cameras.isEmpty) {
      if (cameras.isEmpty) {
        error = 'No camera or webcam found';
        notifyListeners();
      }
      return;
    }
    _initializing = true;
    error = null;
    final preferredIndex = cameras.indexWhere(
      (camera) => camera.lensDirection == preferred,
    );
    if (preferredIndex >= 0) _index = preferredIndex;
    await _openCurrent();
    _initializing = false;
  }

  Future<void> _openCurrent() async {
    final old = controller;
    controller = null;
    await old?.dispose();
    try {
      final next = CameraController(
        cameras[_index],
        ResolutionPreset.high,
        enableAudio: true,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.nv21,
      );
      controller = next;
      await next.initialize();
      await next.setFlashMode(FlashMode.off);
      error = null;
      await faceTracking.start(next);
    } on CameraException catch (exception) {
      controller = null;
      error = exception.code == 'CameraAccessDenied'
          ? 'Please allow SpeakUp to use your camera'
          : 'Could not open the camera (${exception.code})';
    } catch (_) {
      controller = null;
      error = 'Could not open the camera';
    }
    notifyListeners();
  }

  Future<void> flip() async {
    if (_initializing || cameras.length < 2) return;
    _initializing = true;
    _index = (_index + 1) % cameras.length;
    await _openCurrent();
    _initializing = false;
  }

  Future<void> toggle() async {
    isEnabled = !isEnabled;
    await faceTracking.start(controller);
    notifyListeners();
  }

  Future<void> prepareForVideoRecording() async {
    var active = controller;
    if (active == null || !active.value.isInitialized) {
      await initialize(
        preferred: cameras.isEmpty
            ? CameraLensDirection.front
            : cameras[_index].lensDirection,
      );
      active = controller;
    }
    if (active == null || !active.value.isInitialized) {
      throw StateError('The camera is not ready.');
    }
    if (active.value.isRecordingVideo) {
      throw StateError('The previous recording is still being finalized.');
    }
    await faceTracking.stop();
    if (!isEnabled) await faceTracking.prepareForVideoFrames(active);
  }

  Future<void> recoverForVideoRecording() async {
    await faceTracking.stop();
    final old = controller;
    controller = null;
    await old?.dispose();
    await _openCurrent();
  }

  Future<void> resumeAvatarTracking() async {
    await faceTracking.start(controller);
  }

  Future<void> pause() async {
    await faceTracking.stop();
    final old = controller;
    controller = null;
    await old?.dispose();
    notifyListeners();
  }

  Future<void> resume() {
    return initialize(
      preferred: cameras.isEmpty
          ? CameraLensDirection.front
          : cameras[_index].lensDirection,
    );
  }

  @override
  void dispose() {
    faceTracking.dispose();
    controller?.dispose();
    super.dispose();
  }
}
