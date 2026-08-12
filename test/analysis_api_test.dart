import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speak_up/analysis_api.dart';
import 'package:speak_up/models.dart';
import 'package:speak_up/transcription_service.dart';

void main() {
  test(
    'analysis API sends transcript data and parses structured results',
    () async {
      final client = MockClient((request) async {
        final input = jsonDecode(request.body) as Map<String, dynamic>;
        expect(input['topic'], 'A calm place');
        expect(input['transcript'], contains('park'));
        return http.Response(
          jsonEncode({
            'overallScore': 81,
            'categoryScores': {
              'Fluency': 80,
              'Content': 84,
              'Structure': 79,
              'Vocabulary': 77,
              'Grammar': 75,
              'Pronunciation': 82,
            },
            'strengths': ['Clear main idea', 'Relevant example'],
            'improvements': ['Use past tense consistently', 'Add a transition'],
            'transcriptSentences': [
              {
                'original': 'I go to the park yesterday.',
                'correction': 'I went to the park yesterday.',
                'note': 'Use the simple past for a completed action.',
                'startMs': 0,
                'endMs': 2500,
              },
            ],
            'revisedVersion': 'I went to the park yesterday and felt calm.',
            'revisedChanges': ['Corrected tense', 'Improved flow'],
            'repeatedWords': {'park': 2},
          }),
          200,
        );
      });
      final api = AnalysisApi(client: client);
      final result = await api.analyze(
        topic: 'A calm place',
        difficulty: Difficulty.easy,
        durationSeconds: 10,
        transcription: const TranscriptionResult(
          text: 'I go to the park yesterday.',
          segments: [
            TranscriptSegment(
              text: 'I go to the park yesterday.',
              startMs: 0,
              endMs: 2500,
            ),
          ],
        ),
      );
      expect(result.overallScore, 81);
      expect(
        result.transcriptSentences.single.correction,
        'I went to the park yesterday.',
      );
      expect(result.revisedChanges, hasLength(2));
      api.close();
    },
  );
}
