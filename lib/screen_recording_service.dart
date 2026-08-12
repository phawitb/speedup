import 'package:flutter/services.dart';

class ScreenRecordingService {
  static const _channel = MethodChannel('com.speakup.app/screen_recording');

  String? pendingVideoPath;
  String? error;
  bool isRecording = false;

  Future<bool> needsSeparateAudio() async {
    try {
      return await _channel.invokeMethod<bool>('needsSeparateAudio') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> start() async {
    try {
      await _channel.invokeMethod<void>('start');
      isRecording = true;
      error = null;
    } on PlatformException catch (exception) {
      error = exception.message ?? 'Screen recording is unavailable';
    } on MissingPluginException {
      error = 'Screen recording is only available on a physical iPhone';
    }
  }

  Future<void> stop() async {
    if (!isRecording) return;
    try {
      pendingVideoPath = await _channel.invokeMethod<String>('stop');
      error = null;
    } on PlatformException catch (exception) {
      error = exception.message ?? 'Could not finish the recording';
    } finally {
      isRecording = false;
    }
  }

  Future<void> save() async {
    final path = pendingVideoPath;
    if (path == null) {
      throw PlatformException(
        code: 'no_recording',
        message: error ?? 'No recorded video is available',
      );
    }
    await _channel.invokeMethod<void>('save', {'path': path});
  }

  Future<void> discard() async {
    if (isRecording) {
      try {
        await _channel.invokeMethod<void>('discardActive');
      } on PlatformException {
        // The OS may already have stopped the recording.
      }
      isRecording = false;
    }
    final path = pendingVideoPath;
    if (path != null) {
      await _channel.invokeMethod<void>('discard', {'path': path});
      pendingVideoPath = null;
    }
  }
}
