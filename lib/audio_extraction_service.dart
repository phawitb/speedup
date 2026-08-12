import 'package:flutter/services.dart';

class AudioExtractionService {
  static const _channel = MethodChannel('com.speakup.app/audio_extraction');

  Future<String> extractWav(String videoPath) async {
    final path = await _channel.invokeMethod<String>('extractWav', {
      'videoPath': videoPath,
    });
    if (path == null || path.isEmpty) {
      throw PlatformException(
        code: 'empty_audio',
        message: 'The recording did not contain an audio track.',
      );
    }
    return path;
  }

  Future<void> delete(String? path) async {
    if (path == null || path.isEmpty) return;
    await _channel.invokeMethod<void>('deleteAudio', {'path': path});
  }
}
