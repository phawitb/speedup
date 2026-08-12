import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class PracticeAudioService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;

  Future<void> start() async {
    if (!await _recorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    _path =
        '${dir.path}/speakup-mic-${DateTime.now().millisecondsSinceEpoch}.wav';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 256000,
      ),
      path: _path!,
    );
  }

  Future<String?> stop() async => await _recorder.stop() ?? _path;

  Future<void> cancel() async {
    await _recorder.cancel();
    final path = _path;
    if (path != null) await File(path).delete().catchError((_) => File(path));
    _path = null;
  }

  void dispose() => _recorder.dispose();
}
