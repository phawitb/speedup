import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'camera_service.dart';
import 'models.dart';

class DirectVideoRecordingService {
  DirectVideoRecordingService({
    required this.cameraService,
    required this.topic,
    required this.day,
    required this.durationSeconds,
    required this.avatarStyle,
  });

  static const _channel = MethodChannel('com.speakup.app/video_composer');
  static const _galleryChannel = MethodChannel(
    'com.speakup.app/screen_recording',
  );

  final CameraService cameraService;
  final String topic;
  final int day;
  final int durationSeconds;
  final AvatarStyle avatarStyle;

  String? pendingVideoPath;
  String? error;
  bool isRecording = false;
  bool _saved = false;
  Timer? _sampleTimer;
  final List<Map<String, Object>> _faceSamples = [];
  DateTime? _startedAt;

  Future<void> start() async {
    if (isRecording) return;
    _sampleTimer?.cancel();
    _sampleTimer = null;
    _faceSamples.clear();
    pendingVideoPath = null;
    _saved = false;
    error = null;
    await _start(retryAfterRecovery: true);
  }

  Future<void> _start({required bool retryAfterRecovery}) async {
    try {
      await cameraService.prepareForVideoRecording();
      final controller = cameraService.controller;
      if (controller == null || !controller.value.isInitialized) {
        throw StateError('The camera is not ready.');
      }
      _startedAt = DateTime.now();
      if (!cameraService.isEnabled) {
        _sampleTimer = Timer.periodic(const Duration(milliseconds: 66), (_) {
          final state = cameraService.faceTracking.state;
          _faceSamples.add({
            'timeMs': DateTime.now().difference(_startedAt!).inMilliseconds,
            'yaw': state.yaw,
            'pitch': state.pitch,
            'roll': state.roll,
            'leftEye': state.leftEye,
            'rightEye': state.rightEye,
            'mouthOpen': state.mouthOpen,
            'smile': state.smile,
          });
        });
      }
      await controller
          .startVideoRecording(
            onAvailable: cameraService.isEnabled
                ? null
                : cameraService.faceTracking.processVideoFrame,
          )
          .timeout(const Duration(seconds: 8));
      isRecording = true;
      error = null;
    } catch (exception) {
      _sampleTimer?.cancel();
      _sampleTimer = null;
      error = exception.toString();
      isRecording = false;
      if (retryAfterRecovery) {
        try {
          await cameraService.recoverForVideoRecording();
          return await _start(retryAfterRecovery: false);
        } catch (recoveryError) {
          error = recoveryError.toString();
        }
      }
      await cameraService.resumeAvatarTracking();
    }
  }

  Future<void> stop() async {
    if (!isRecording) return;
    _sampleTimer?.cancel();
    _sampleTimer = null;
    try {
      final raw = await cameraService.controller!.stopVideoRecording();
      isRecording = false;
      await cameraService.resumeAvatarTracking();
      if (Platform.isAndroid) {
        pendingVideoPath = await _channel
            .invokeMethod<String>('compose', {
              'inputPath': raw.path,
              'topic': topic,
              'day': day,
              'durationSeconds': durationSeconds,
              'avatarMode': !cameraService.isEnabled,
              'avatarCat': avatarStyle.cat,
              'avatarScarf': avatarStyle.scarf,
              'avatarBackground': avatarStyle.background,
              'faceSamples': _faceSamples,
            })
            .timeout(
              const Duration(minutes: 2),
              onTimeout: () => throw TimeoutException(
                'Video processing took too long. Please record again.',
              ),
            );
        try {
          await File(raw.path).delete();
        } catch (_) {}
      } else {
        // iOS records directly without ReplayKit. Native composition can be
        // added independently; the source movie already contains camera audio.
        pendingVideoPath = raw.path;
      }
      if (pendingVideoPath == null) {
        throw StateError('Video export returned no file.');
      }
      error = null;
    } catch (exception) {
      error = exception.toString();
      isRecording = false;
      await cameraService.resumeAvatarTracking();
      rethrow;
    }
  }

  Future<void> save() async {
    final path = pendingVideoPath;
    if (path == null) {
      throw StateError(error ?? 'No recorded video is available.');
    }
    if (_saved) return;
    await _galleryChannel.invokeMethod<void>('save', {'path': path});
    _saved = true;
  }

  Future<void> discard() async {
    _sampleTimer?.cancel();
    _sampleTimer = null;
    if (isRecording) {
      try {
        final file = await cameraService.controller?.stopVideoRecording();
        if (file != null) await File(file.path).delete();
      } catch (_) {}
      isRecording = false;
    }
    final path = pendingVideoPath;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    pendingVideoPath = null;
    await cameraService.resumeAvatarTracking();
  }
}
