import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'transcription_service.dart';

class AnalysisApiException implements Exception {
  const AnalysisApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AnalysisApi {
  AnalysisApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static String get defaultBaseUrl {
    const configured = String.fromEnvironment('SPEAKUP_BACKEND_URL');
    if (configured.isNotEmpty) return configured;
    return 'http://127.0.0.1:8787';
  }

  Future<AnalysisResult> analyze({
    required String topic,
    required Difficulty difficulty,
    required int durationSeconds,
    required TranscriptionResult transcription,
  }) async {
    late http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$defaultBaseUrl/analyze'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'topic': topic,
              'difficulty': difficulty.name,
              'durationSeconds': durationSeconds,
              'transcript': transcription.text,
              'segments': transcription.segments
                  .map((item) => item.toJson())
                  .toList(),
              'deliveryMetrics': {
                'wordsPerMinute': durationSeconds == 0
                    ? 0
                    : (transcription.text.split(RegExp(r'\s+')).length *
                              60 /
                              durationSeconds)
                          .round(),
                'recordedDurationSeconds': durationSeconds,
              },
            }),
          )
          .timeout(const Duration(minutes: 3));
    } on TimeoutException {
      throw const AnalysisApiException(
        'The analysis server is taking longer than expected. Your transcript is safe — tap Try Again to retry only the analysis.',
      );
    } on SocketException {
      throw AnalysisApiException(
        'Could not reach the SpeakUp analysis server at $defaultBaseUrl.',
      );
    } catch (error) {
      throw AnalysisApiException('Analysis request failed: $error');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AnalysisApiException(
        body['error'] as String? ?? 'Analysis failed (${response.statusCode}).',
      );
    }
    return AnalysisResult.fromJson(body);
  }

  void close() => _client.close();
}
