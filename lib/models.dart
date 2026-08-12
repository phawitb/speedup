enum Difficulty { random, easy, medium, hard }

enum RecordingStatus { idle, recording, finished }

class AvatarStyle {
  const AvatarStyle({
    this.cat = 'White',
    this.scarf = 'Teal',
    this.background = 'Mint',
  });

  final String cat;
  final String scarf;
  final String background;

  AvatarStyle copyWith({String? cat, String? scarf, String? background}) =>
      AvatarStyle(
        cat: cat ?? this.cat,
        scarf: scarf ?? this.scarf,
        background: background ?? this.background,
      );
}

class PracticeSettings {
  const PracticeSettings({
    this.difficulty = Difficulty.random,
    this.topicCategory = 'Random',
    this.durationSeconds = 60,
  });

  final Difficulty difficulty;
  final String topicCategory;
  final int durationSeconds;

  PracticeSettings copyWith({
    Difficulty? difficulty,
    String? topicCategory,
    int? durationSeconds,
  }) => PracticeSettings(
    difficulty: difficulty ?? this.difficulty,
    topicCategory: topicCategory ?? this.topicCategory,
    durationSeconds: durationSeconds ?? this.durationSeconds,
  );
}

class PracticeSession {
  const PracticeSession({
    required this.topic,
    this.elapsedSeconds = 0,
    this.status = RecordingStatus.idle,
  });

  final String topic;
  final int elapsedSeconds;
  final RecordingStatus status;

  PracticeSession copyWith({
    String? topic,
    int? elapsedSeconds,
    RecordingStatus? status,
  }) => PracticeSession(
    topic: topic ?? this.topic,
    elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
    status: status ?? this.status,
  );
}

class AnalysisResult {
  const AnalysisResult({
    required this.overallScore,
    required this.categoryScores,
    required this.strengths,
    required this.improvements,
    required this.transcriptSentences,
    required this.revisedVersion,
    required this.revisedChanges,
    required this.repeatedWords,
  });

  final int overallScore;
  final Map<String, int> categoryScores;
  final List<String> strengths;
  final List<String> improvements;
  final List<TranscriptSentence> transcriptSentences;
  final String revisedVersion;
  final List<String> revisedChanges;
  final Map<String, int> repeatedWords;

  Map<String, Object?> toJson() => {
    'overallScore': overallScore,
    'categoryScores': categoryScores,
    'strengths': strengths,
    'improvements': improvements,
    'transcriptSentences': transcriptSentences
        .map((item) => item.toJson())
        .toList(),
    'revisedVersion': revisedVersion,
    'revisedChanges': revisedChanges,
    'repeatedWords': repeatedWords,
  };

  factory AnalysisResult.fromJson(Map<String, dynamic> json) => AnalysisResult(
    overallScore: (json['overallScore'] as num).round().clamp(0, 100),
    categoryScores: (json['categoryScores'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, (value as num).round().clamp(0, 100)),
    ),
    strengths: List<String>.from(json['strengths'] as List),
    improvements: List<String>.from(json['improvements'] as List),
    transcriptSentences: (json['transcriptSentences'] as List)
        .map(
          (item) => TranscriptSentence.fromJson(item as Map<String, dynamic>),
        )
        .toList(),
    revisedVersion: json['revisedVersion'] as String,
    revisedChanges: List<String>.from(
      json['revisedChanges'] as List? ?? const [],
    ),
    repeatedWords: (json['repeatedWords'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, (value as num).round()),
    ),
  );

  static const sample = AnalysisResult(
    overallScore: 82,
    categoryScores: {
      'Fluency': 84,
      'Content': 80,
      'Structure': 81,
      'Vocabulary': 78,
      'Grammar': 76,
      'Pronunciation': 82,
    },
    strengths: [
      'Clear structure',
      'Good supporting examples',
      'Confident tone',
    ],
    improvements: [
      'Use fewer filler words such as “um” and “like”',
      'Use a wider range of vocabulary',
      'Connect ideas with smoother transitions',
    ],
    transcriptSentences: [
      TranscriptSentence(
        original:
            'If I could live in any fictional world, I will choose Hogwarts from Harry Potter.',
        correction:
            'If I could live in any fictional world, I would choose Hogwarts from Harry Potter.',
        note: 'Use “would” for an imagined situation.',
      ),
      TranscriptSentence(
        original:
            'I love the atmosphere of magic, the friendships, and the adventures.',
      ),
      TranscriptSentence(
        original:
            'It would be amazing to learn spells, ride a broomstick, and explore the castle.',
      ),
      TranscriptSentence(
        original:
            'Most important, I could grow up in a place where good always fight against evil.',
        correction:
            'Most importantly, I could grow up in a place where good always fights against evil.',
        note:
            'Use the adverb “importantly” and match the singular subject “good” with “fights”.',
      ),
    ],
    revisedVersion:
        'If I could step into any fictional world, I would choose Hogwarts from Harry Potter. Its magical atmosphere, close friendships, and sense of adventure have always fascinated me. I would love to learn spells, fly on a broomstick, and explore every corner of the castle. Above all, Hogwarts feels like a place where courage and friendship can overcome evil, which is why I would be thrilled to call it home.',
    revisedChanges: [
      'Stronger opening sentence',
      'Smoother transitions between ideas',
      'More precise and expressive vocabulary',
      'A memorable closing thought',
    ],
    repeatedWords: {'um': 5, 'like': 3, 'you know': 2, 'actually': 1},
  );
}

class TranscriptSentence {
  const TranscriptSentence({
    required this.original,
    this.correction,
    this.note,
    this.startMs = 0,
    this.endMs = 0,
  });
  final String original;
  final String? correction;
  final String? note;
  final int startMs;
  final int endMs;
  bool get needsCorrection => correction != null;

  Map<String, Object?> toJson() => {
    'original': original,
    'correction': correction,
    'note': note,
    'startMs': startMs,
    'endMs': endMs,
  };

  factory TranscriptSentence.fromJson(Map<String, dynamic> json) =>
      TranscriptSentence(
        original: json['original'] as String,
        correction: json['correction'] as String?,
        note: json['note'] as String?,
        startMs: (json['startMs'] as num?)?.round() ?? 0,
        endMs: (json['endMs'] as num?)?.round() ?? 0,
      );
}

class StreakState {
  const StreakState({this.currentDay = 1, this.lastPracticeDate});
  final int currentDay;
  final DateTime? lastPracticeDate;
}

class PracticeHistoryItem {
  const PracticeHistoryItem({
    required this.topic,
    required this.date,
    required this.durationSeconds,
    required this.score,
    required this.result,
  });
  final String topic;
  final DateTime date;
  final int durationSeconds;
  final int score;
  final AnalysisResult result;

  Map<String, Object> toJson() => {
    'topic': topic,
    'date': date.toIso8601String(),
    'duration': durationSeconds,
    'score': score,
    'result': result.toJson(),
  };
  factory PracticeHistoryItem.fromJson(Map<String, dynamic> json) =>
      PracticeHistoryItem(
        topic: json['topic'] as String,
        date: DateTime.parse(json['date'] as String),
        durationSeconds: json['duration'] as int,
        score: json['score'] as int,
        result: json['result'] == null
            ? AnalysisResult.sample
            : AnalysisResult.fromJson(json['result'] as Map<String, dynamic>),
      );
}
