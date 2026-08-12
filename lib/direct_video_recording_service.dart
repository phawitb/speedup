import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
  static const _progressChannel = EventChannel(
    'com.speakup.app/video_composer_progress',
  );
  static const _galleryChannel = MethodChannel(
    'com.speakup.app/screen_recording',
  );

  final CameraService cameraService;
  final String topic;
  final int day;
  final int durationSeconds;
  final AvatarStyle avatarStyle;

  String? pendingVideoPath;
  String? _rawVideoPath;
  String? error;
  bool isRecording = false;
  bool isPrepared = false;
  bool _saved = false;
  Timer? _sampleTimer;
  final List<Map<String, Object>> _faceSamples = [];
  DateTime? _startedAt;
  StreamSubscription<dynamic>? _progressSubscription;
  final ValueNotifier<double> exportProgress = ValueNotifier<double>(0);
  final ValueNotifier<String> exportStage = ValueNotifier<String>(
    'Preparing video',
  );

  Future<void> start() async {
    if (isRecording) return;
    _sampleTimer?.cancel();
    _sampleTimer = null;
    _faceSamples.clear();
    pendingVideoPath = null;
    _rawVideoPath = null;
    isPrepared = false;
    _saved = false;
    error = null;
    exportProgress.value = 0;
    exportStage.value = 'Preparing video';
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
      _rawVideoPath = raw.path;
      pendingVideoPath = raw.path;
      isPrepared = !Platform.isAndroid;
      error = null;
    } catch (exception) {
      error = exception.toString();
      isRecording = false;
      await cameraService.resumeAvatarTracking();
      rethrow;
    }
  }

  Future<void> save({
    List<Map<String, Object?>> transcriptSegments = const [],
  }) async {
    await prepare(transcriptSegments: transcriptSegments);
    final path = pendingVideoPath;
    if (path == null) {
      throw StateError(error ?? 'No recorded video is available.');
    }
    if (_saved) return;
    await _galleryChannel.invokeMethod<void>('save', {'path': path});
    _saved = true;
  }

  Future<String> prepare({
    List<Map<String, Object?>> transcriptSegments = const [],
  }) async {
    final rawPath = _rawVideoPath ?? pendingVideoPath;
    if (rawPath == null) {
      throw StateError(error ?? 'No recorded video is available.');
    }
    if (isPrepared) return pendingVideoPath ?? rawPath;
    if (!Platform.isAndroid) {
      pendingVideoPath = rawPath;
      isPrepared = true;
      return rawPath;
    }
    try {
      exportStage.value = transcriptSegments.isEmpty
          ? 'Composing video'
          : 'Adding transcript';
      final progressBase = transcriptSegments.isEmpty ? 0.0 : .35;
      final progressRange = transcriptSegments.isEmpty ? 1.0 : .65;
      exportProgress.value = progressBase;
      await _progressSubscription?.cancel();
      _progressSubscription = _progressChannel.receiveBroadcastStream().listen((
        value,
      ) {
        if (value is num) {
          exportProgress.value =
              (progressBase + value.toDouble() * progressRange).clamp(0.0, 1.0);
        }
      });
      final composedPath = await _channel
          .invokeMethod<String>('compose', {
            'inputPath': rawPath,
            'topic': topic,
            'day': day,
            'durationSeconds': durationSeconds,
            'avatarMode': !cameraService.isEnabled,
            'avatarCat': avatarStyle.cat,
            'avatarScarf': avatarStyle.scarf,
            'avatarBackground': avatarStyle.background,
            'faceSamples': _faceSamples,
            'transcriptSegments': transcriptSegments,
          })
          .timeout(
            const Duration(minutes: 2),
            onTimeout: () => throw TimeoutException(
              'Video processing took too long. Please record again.',
            ),
          );
      if (composedPath == null) {
        throw StateError('Video export returned no file.');
      }
      pendingVideoPath = composedPath;
      isPrepared = true;
      exportProgress.value = 1;
      exportStage.value = 'Video ready';
      await _progressSubscription?.cancel();
      _progressSubscription = null;
      if (rawPath != composedPath) {
        try {
          await File(rawPath).delete();
        } catch (_) {}
      }
      return composedPath;
    } catch (exception) {
      error = exception.toString();
      await _progressSubscription?.cancel();
      _progressSubscription = null;
      rethrow;
    }
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

  void dispose() {
    _sampleTimer?.cancel();
    unawaited(_progressSubscription?.cancel());
    exportProgress.dispose();
    exportStage.dispose();
  }
}
