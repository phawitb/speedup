import 'package:whisper_flutter_new/whisper_flutter_new.dart';

class TranscriptSegment {
  const TranscriptSegment({
    required this.text,
    required this.startMs,
    required this.endMs,
  });
  final String text;
  final int startMs;
  final int endMs;

  Map<String, Object> toJson() => {
    'text': text,
    'startMs': startMs,
    'endMs': endMs,
  };
}

class TranscriptionResult {
  const TranscriptionResult({required this.text, required this.segments});
  final String text;
  final List<TranscriptSegment> segments;
}

class TranscriptionService {
  const TranscriptionService();

  static const _whisper = Whisper(model: WhisperModel.base);

  Future<TranscriptionResult> transcribe(String wavPath) async {
    final response = await _whisper.transcribe(
      transcribeRequest: TranscribeRequest(
        audio: wavPath,
        language: 'en',
        isTranslate: false,
        isNoTimestamps: false,
        splitOnWord: false,
        threads: 4,
        nProcessors: 1,
      ),
    );
    final text = response.text.trim();
    if (text.isEmpty) {
      throw StateError('No speech was detected in this recording.');
    }
    return TranscriptionResult(
      text: text,
      segments: (response.segments ?? const [])
          .map(
            (segment) => TranscriptSegment(
              text: segment.text.trim(),
              startMs: segment.fromTs.inMilliseconds,
              endMs: segment.toTs.inMilliseconds,
            ),
          )
          .where((segment) => segment.text.isNotEmpty)
          .toList(),
    );
  }
}
