import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class AppController extends ChangeNotifier {
  AppController._(this._prefs);
  final SharedPreferences _prefs;

  PracticeSettings settings = const PracticeSettings();
  PracticeSession session = const PracticeSession(
    topic:
        'If you could live in any fictional world, where would you live and why?',
  );
  StreakState streak = const StreakState();
  AvatarStyle avatarStyle = const AvatarStyle();
  AnalysisResult result = AnalysisResult.sample;
  List<PracticeHistoryItem> history = [];
  bool isRandomizing = false;

  static const topics = <String>[
    'If you could live in any fictional world, where would you live and why?',
    'What small habit has made the biggest difference in your life?',
    'If you could master one skill instantly, what would it be and why?',
    'Describe a place that always makes you feel calm and happy.',
  ];

  List<String> get _activeTopics => _topicBank(
    category: settings.topicCategory,
    difficulty: settings.difficulty,
  );

  static Future<AppController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final controller = AppController._(prefs);
    controller.settings = PracticeSettings(
      difficulty: Difficulty.values[prefs.getInt('difficulty') ?? 0],
      topicCategory: prefs.getString('category') ?? 'Random',
      durationSeconds: prefs.getInt('duration') ?? 60,
    );
    controller.session = PracticeSession(
      topic: prefs.getString('topic') ?? topics.first,
    );
    controller.streak = StreakState(
      currentDay: prefs.getInt('streak') ?? 1,
      lastPracticeDate: DateTime.tryParse(
        prefs.getString('lastPractice') ?? '',
      ),
    );
    controller.avatarStyle = AvatarStyle(
      cat: prefs.getString('avatarCat') ?? 'White',
      scarf: prefs.getString('avatarScarf') ?? 'Teal',
      background: prefs.getString('avatarBackground') ?? 'Mint',
    );
    final storedHistory = prefs.getStringList('history') ?? const [];
    controller.history = storedHistory
        .map((item) {
          try {
            return PracticeHistoryItem.fromJson(
              jsonDecode(item) as Map<String, dynamic>,
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<PracticeHistoryItem>()
        .toList();
    return controller;
  }

  Future<void> updateAvatarStyle(AvatarStyle value) async {
    avatarStyle = value;
    notifyListeners();
    await Future.wait([
      _prefs.setString('avatarCat', value.cat),
      _prefs.setString('avatarScarf', value.scarf),
      _prefs.setString('avatarBackground', value.background),
    ]);
  }

  Future<void> updateSettings(PracticeSettings value) async {
    settings = value;
    notifyListeners();
    await Future.wait([
      _prefs.setInt('difficulty', value.difficulty.index),
      _prefs.setString('category', value.topicCategory),
      _prefs.setInt('duration', value.durationSeconds),
    ]);
  }

  void setElapsed(int seconds) {
    session = session.copyWith(
      elapsedSeconds: seconds,
      status: RecordingStatus.recording,
    );
    notifyListeners();
  }

  void setAnalysisResult(AnalysisResult value) {
    result = value;
    notifyListeners();
  }

  void resetSession({bool newTopic = false}) {
    var topic = session.topic;
    if (newTopic) {
      topic = _pickUnusedTopic();
      _prefs.setString('topic', topic);
    }
    session = PracticeSession(topic: topic);
    notifyListeners();
  }

  Future<void> randomizeTopic() async {
    if (isRandomizing) return;
    isRandomizing = true;
    try {
      final original = session.topic;
      final activeTopics = _activeTopics;
      var index = math.max(0, activeTopics.indexOf(original));
      for (var turn = 0; turn < 9; turn++) {
        final stepBase = math.max(1, activeTopics.length - 1).toInt();
        index = (index + 1 + (turn % stepBase)) % activeTopics.length;
        session = PracticeSession(topic: activeTopics[index]);
        notifyListeners();
        await Future<void>.delayed(Duration(milliseconds: 75 + turn * 10));
      }
      session = PracticeSession(topic: _pickUnusedTopic(excluding: original));
      notifyListeners();
      await _prefs.setString('topic', session.topic);
    } finally {
      isRandomizing = false;
      notifyListeners();
    }
  }

  String _pickUnusedTopic({String? excluding}) {
    final bank = _activeTopics;
    final key = _usedTopicKey();
    final used = (_prefs.getStringList(key) ?? const <String>[]).toSet();
    var available = bank
        .where((topic) => !used.contains(topic) && topic != excluding)
        .toList();
    if (available.isEmpty) {
      used.clear();
      available = bank.where((topic) => topic != excluding).toList();
      if (available.isEmpty) available = List<String>.from(bank);
    }
    final selected = available[math.Random().nextInt(available.length)];
    used.add(selected);
    _prefs.setStringList(key, used.toList());
    return selected;
  }

  String _usedTopicKey() =>
      'usedTopics.${settings.topicCategory}.${settings.difficulty.name}';

  Future<void> completePractice() async {
    final now = DateTime.now();
    final last = streak.lastPracticeDate;
    final isNewDay =
        last == null ||
        last.year != now.year ||
        last.month != now.month ||
        last.day != now.day;
    if (isNewDay && last != null) {
      streak = StreakState(
        currentDay: streak.currentDay + 1,
        lastPracticeDate: now,
      );
    } else {
      streak = StreakState(
        currentDay: streak.currentDay,
        lastPracticeDate: now,
      );
    }
    await _prefs.setInt('streak', streak.currentDay);
    await _prefs.setString('lastPractice', now.toIso8601String());
    history.insert(
      0,
      PracticeHistoryItem(
        topic: session.topic,
        date: now,
        durationSeconds: session.elapsedSeconds,
        score: result.overallScore,
        result: result,
      ),
    );
    if (history.length > 30) history = history.take(30).toList();
    await _prefs.setStringList(
      'history',
      history.map((item) => jsonEncode(item.toJson())).toList(),
    );
    notifyListeners();
  }
}

List<String> _topicBank({
  required String category,
  required Difficulty difficulty,
}) {
  final categories = category == 'Random'
      ? const ['General', 'Tech', 'Finance', 'IELTS', 'Gen Z']
      : [category];
  if (category == 'Word') {
    return _wordBank(difficulty);
  }
  final difficulties = difficulty == Difficulty.random
      ? const [Difficulty.easy, Difficulty.medium, Difficulty.hard]
      : [difficulty];
  final bank = <String>[];
  for (final currentCategory in categories) {
    for (final currentDifficulty in difficulties) {
      bank.addAll(
        _speakingBank(category: currentCategory, difficulty: currentDifficulty),
      );
    }
  }
  return bank;
}

List<String> _speakingBank({
  required String category,
  required Difficulty difficulty,
}) {
  final subjects = _categorySubjects[category] ?? _categorySubjects['General']!;
  final prompts = switch (difficulty) {
    Difficulty.easy => _easyFrames,
    Difficulty.medium => _mediumFrames,
    Difficulty.hard => _hardFrames,
    Difficulty.random => _mediumFrames,
  };
  return [
    for (final subject in subjects)
      for (final prompt in prompts) prompt.replaceAll('{subject}', subject),
  ];
}

List<String> _wordBank(Difficulty difficulty) {
  final words = switch (difficulty) {
    Difficulty.easy => _easyWords,
    Difficulty.medium => _mediumWords,
    Difficulty.hard => _hardWords,
    Difficulty.random => [..._easyWords, ..._mediumWords, ..._hardWords],
  };
  return [
    for (final word in words.take(100))
      '${word.word}\n${word.definition}\n${word.example}',
  ];
}

const _categorySubjects = <String, List<String>>{
  'General': [
    'a place that makes you feel calm',
    'a small habit that changed your life',
    'a person who inspires you',
    'a meal you never get tired of',
    'a childhood memory you still remember clearly',
    'a skill you want to master',
    'a weekend that felt perfect',
    'a book, movie, or game that stayed with you',
    'a challenge that taught you something',
    'a future version of your ideal day',
  ],
  'Tech': [
    'an app you use every day',
    'a piece of technology that saves time',
    'artificial intelligence in daily life',
    'online privacy and personal data',
    'a gadget you would redesign',
    'remote work tools',
    'social media algorithms',
    'digital learning',
    'smart homes',
    'the future of smartphones',
  ],
  'Finance': [
    'a smart saving habit',
    'budgeting for your goals',
    'cashless payments',
    'buying things you truly need',
    'investing for beginners',
    'financial mistakes people learn from',
    'side income ideas',
    'planning for emergencies',
    'the value of time and money',
    'how advertising affects spending',
  ],
  'IELTS': [
    'your hometown',
    'a memorable journey',
    'environmental responsibility',
    'education and confidence',
    'public transport',
    'a useful skill for young people',
    'work-life balance',
    'healthy lifestyles',
    'a leader you respect',
    'technology in education',
  ],
  'Gen Z': [
    'a social media trend',
    'short-form videos',
    'online communities',
    'personal style',
    'memes as communication',
    'digital friendships',
    'creator culture',
    'mental health conversations',
    'music that defines a moment',
    'how young people learn online',
  ],
};

const _easyFrames = [
  'Describe {subject}.',
  'Talk about {subject} and why you like it.',
  'What do you enjoy about {subject}?',
  'Explain {subject} in a simple way.',
  'Tell a short story about {subject}.',
  'What is one thing people should know about {subject}?',
  'How does {subject} make you feel?',
  'When did you first notice {subject}?',
  'Why is {subject} important to you?',
  'Give one example related to {subject}.',
];

const _mediumFrames = [
  'Describe how {subject} affects your daily life.',
  'Compare {subject} with a similar idea.',
  'Explain one benefit and one drawback of {subject}.',
  'Tell a story about {subject} and what you learned.',
  'What would you change about {subject}, and why?',
  'How could {subject} improve in the future?',
  'Why might people feel differently about {subject}?',
  'Suggest one solution for a problem with {subject}.',
  'What does {subject} reveal about your values?',
  'Give a balanced opinion on {subject}.',
];

const _hardFrames = [
  'Analyze the long-term impact of {subject}.',
  'Argue for or against a common belief about {subject}.',
  'Discuss a trade-off connected to {subject}.',
  'Explain how {subject} may change in ten years.',
  'Evaluate whether {subject} is overrated or underrated.',
  'Use a personal example to support a point about {subject}.',
  'How might culture or age shape views on {subject}?',
  'Propose a realistic improvement for {subject}.',
  'Explain one hidden cause and result of {subject}.',
  'Give a nuanced answer with both sides of {subject}.',
];

class _WordEntry {
  const _WordEntry(this.word, this.definition, this.example);
  final String word;
  final String definition;
  final String example;
}

const _baseWords = [
  _WordEntry(
    'resilient',
    'able to recover quickly after difficulty',
    'She stayed resilient after a difficult week.',
  ),
  _WordEntry(
    'thoughtful',
    'showing care and careful consideration',
    'That was a thoughtful answer to a hard question.',
  ),
  _WordEntry(
    'convenient',
    'easy to use or suitable for the situation',
    'Online booking is convenient when I am busy.',
  ),
  _WordEntry(
    'meaningful',
    'important or valuable in a personal way',
    'The conversation felt meaningful because it was honest.',
  ),
  _WordEntry(
    'confident',
    'feeling sure about your ability',
    'I feel more confident when I prepare first.',
  ),
  _WordEntry(
    'curious',
    'wanting to learn or know more',
    'Curious people ask better questions.',
  ),
  _WordEntry(
    'focused',
    'paying clear attention to one thing',
    'I work better when I stay focused.',
  ),
  _WordEntry(
    'patient',
    'able to wait calmly',
    'A patient speaker gives ideas time to develop.',
  ),
  _WordEntry(
    'creative',
    'able to make new or original ideas',
    'A creative answer can make a simple topic interesting.',
  ),
  _WordEntry(
    'honest',
    'telling the truth and being sincere',
    'An honest story is often easier to remember.',
  ),
  _WordEntry(
    'efficient',
    'working well without wasting time',
    'A checklist makes my routine more efficient.',
  ),
  _WordEntry(
    'reliable',
    'able to be trusted',
    'A reliable friend keeps their promises.',
  ),
  _WordEntry(
    'flexible',
    'able to change when needed',
    'Flexible plans help me handle surprises.',
  ),
  _WordEntry(
    'balanced',
    'giving fair attention to different sides',
    'A balanced opinion sounds more mature.',
  ),
  _WordEntry(
    'practical',
    'useful in real situations',
    'This is a practical solution for students.',
  ),
  _WordEntry(
    'memorable',
    'easy to remember',
    'The trip was memorable because everything felt new.',
  ),
  _WordEntry(
    'valuable',
    'useful, important, or worth something',
    'Feedback is valuable when it is specific.',
  ),
  _WordEntry(
    'supportive',
    'helping or encouraging someone',
    'My family is supportive of my goals.',
  ),
  _WordEntry(
    'independent',
    'able to do things without relying on others',
    'Learning English makes me feel more independent.',
  ),
  _WordEntry(
    'organized',
    'arranged clearly and effectively',
    'An organized answer is easier to follow.',
  ),
  _WordEntry(
    'adaptable',
    'able to adjust to new conditions',
    'Adaptable people learn quickly in new jobs.',
  ),
  _WordEntry(
    'ambitious',
    'strongly wanting to succeed',
    'Ambitious goals can push us to improve.',
  ),
  _WordEntry(
    'authentic',
    'real and true to yourself',
    'An authentic story sounds natural.',
  ),
  _WordEntry(
    'consistent',
    'happening in the same reliable way',
    'Consistent practice improves fluency.',
  ),
  _WordEntry(
    'insightful',
    'showing deep understanding',
    'Her comment was insightful and clear.',
  ),
  _WordEntry(
    'resourceful',
    'good at finding ways to solve problems',
    'A resourceful learner uses every tool available.',
  ),
  _WordEntry(
    'strategic',
    'planned carefully to reach a goal',
    'A strategic plan saves time later.',
  ),
  _WordEntry(
    'sustainable',
    'able to continue without causing harm',
    'Walking is a sustainable transport choice.',
  ),
  _WordEntry(
    'collaborative',
    'working well with other people',
    'Collaborative teams solve problems faster.',
  ),
  _WordEntry(
    'persuasive',
    'able to make people agree or act',
    'A persuasive example can change someone’s opinion.',
  ),
  _WordEntry(
    'innovative',
    'using new ideas or methods',
    'Innovative apps can make learning easier.',
  ),
  _WordEntry(
    'analytical',
    'good at studying details and patterns',
    'An analytical speaker explains the reasons clearly.',
  ),
  _WordEntry(
    'empathetic',
    'able to understand other people’s feelings',
    'Empathetic leaders listen before they decide.',
  ),
  _WordEntry(
    'proactive',
    'acting early before problems grow',
    'A proactive student asks for help early.',
  ),
  _WordEntry(
    'intentional',
    'done with a clear purpose',
    'Intentional practice is better than random practice.',
  ),
  _WordEntry(
    'constructive',
    'helpful and focused on improvement',
    'Constructive feedback tells you what to fix.',
  ),
  _WordEntry(
    'credible',
    'easy to believe or trust',
    'Specific evidence makes an argument credible.',
  ),
  _WordEntry(
    'concise',
    'short but clear',
    'A concise answer can still be powerful.',
  ),
  _WordEntry(
    'nuanced',
    'showing small but important differences',
    'A nuanced opinion avoids simple extremes.',
  ),
  _WordEntry(
    'compelling',
    'interesting and convincing',
    'A compelling story keeps people listening.',
  ),
  _WordEntry(
    'transparent',
    'open and easy to understand',
    'Transparent rules make people feel safe.',
  ),
  _WordEntry(
    'accountable',
    'responsible for your actions',
    'Accountable people admit mistakes and improve.',
  ),
  _WordEntry(
    'inclusive',
    'welcoming different kinds of people',
    'Inclusive design helps more users feel comfortable.',
  ),
  _WordEntry(
    'versatile',
    'useful in many different ways',
    'English is versatile because it helps in travel and work.',
  ),
  _WordEntry(
    'efficiently',
    'in a way that saves time and effort',
    'I study efficiently by reviewing small sections.',
  ),
  _WordEntry(
    'gradually',
    'slowly over time',
    'Fluency improves gradually with practice.',
  ),
  _WordEntry(
    'significantly',
    'by a large or important amount',
    'My confidence increased significantly this year.',
  ),
  _WordEntry(
    'ultimately',
    'in the end',
    'Ultimately, communication matters more than perfection.',
  ),
  _WordEntry(
    'specifically',
    'clearly and exactly',
    'Specifically, I want to improve pronunciation.',
  ),
  _WordEntry(
    'meanwhile',
    'at the same time',
    'Meanwhile, I kept practicing every morning.',
  ),
  _WordEntry(
    'therefore',
    'for that reason',
    'I was tired; therefore, I took a short break.',
  ),
  _WordEntry(
    'however',
    'used to introduce a contrast',
    'The idea is simple; however, it is not easy.',
  ),
  _WordEntry(
    'although',
    'even though',
    'Although it was difficult, I kept trying.',
  ),
  _WordEntry(
    'because',
    'for the reason that',
    'I joined the class because I wanted feedback.',
  ),
  _WordEntry(
    'clarify',
    'to make something easier to understand',
    'Could you clarify your main point?',
  ),
  _WordEntry(
    'compare',
    'to look at similarities and differences',
    'I will compare studying alone with studying in a group.',
  ),
  _WordEntry(
    'describe',
    'to say what something is like',
    'Let me describe the place first.',
  ),
  _WordEntry(
    'explain',
    'to make an idea clear',
    'I will explain why this habit matters.',
  ),
  _WordEntry(
    'suggest',
    'to offer an idea or plan',
    'I suggest starting with a simple routine.',
  ),
  _WordEntry(
    'improve',
    'to make something better',
    'Daily speaking can improve fluency.',
  ),
  _WordEntry(
    'achieve',
    'to successfully reach a goal',
    'I want to achieve a higher score.',
  ),
  _WordEntry(
    'reflect',
    'to think carefully about something',
    'I reflect on my mistakes after practice.',
  ),
  _WordEntry(
    'prioritize',
    'to decide what is most important',
    'I prioritize sleep during busy weeks.',
  ),
  _WordEntry(
    'maintain',
    'to keep something going',
    'It is hard to maintain motivation alone.',
  ),
  _WordEntry(
    'overcome',
    'to succeed despite a problem',
    'I overcame my fear of speaking.',
  ),
  _WordEntry(
    'influence',
    'to affect the way someone thinks or acts',
    'Friends can influence our spending habits.',
  ),
  _WordEntry(
    'motivate',
    'to make someone want to do something',
    'Small wins motivate me to continue.',
  ),
  _WordEntry(
    'connect',
    'to build a relationship or link',
    'Stories help people connect with the speaker.',
  ),
  _WordEntry(
    'develop',
    'to grow or become stronger',
    'I want to develop a natural speaking style.',
  ),
  _WordEntry(
    'experience',
    'knowledge or feeling gained from doing something',
    'This experience taught me patience.',
  ),
  _WordEntry(
    'perspective',
    'a way of seeing or thinking about something',
    'Travel changed my perspective on comfort.',
  ),
  _WordEntry(
    'opportunity',
    'a chance to do something useful',
    'Speaking practice is an opportunity to grow.',
  ),
  _WordEntry(
    'challenge',
    'something difficult that tests you',
    'A challenge can reveal your strengths.',
  ),
  _WordEntry(
    'solution',
    'a way to solve a problem',
    'The best solution is simple and realistic.',
  ),
  _WordEntry(
    'advantage',
    'a useful or positive point',
    'One advantage of online learning is flexibility.',
  ),
  _WordEntry(
    'disadvantage',
    'a negative or difficult point',
    'A disadvantage is that it can feel lonely.',
  ),
  _WordEntry(
    'habit',
    'something you do regularly',
    'Reading at night became a relaxing habit.',
  ),
  _WordEntry(
    'routine',
    'a regular way of doing things',
    'My morning routine helps me feel ready.',
  ),
  _WordEntry(
    'decision',
    'a choice you make',
    'That decision changed my schedule.',
  ),
  _WordEntry(
    'responsibility',
    'a duty to do or care for something',
    'Financial responsibility starts with tracking expenses.',
  ),
  _WordEntry(
    'confidence',
    'belief in your own ability',
    'Confidence grows when practice feels safe.',
  ),
  _WordEntry(
    'creativity',
    'the ability to make new ideas',
    'Creativity makes communication more engaging.',
  ),
  _WordEntry(
    'discipline',
    'the ability to keep doing what is needed',
    'Discipline matters when motivation disappears.',
  ),
  _WordEntry(
    'curiosity',
    'a strong wish to learn',
    'Curiosity makes learning feel lighter.',
  ),
  _WordEntry(
    'empathy',
    'the ability to understand someone’s feelings',
    'Empathy improves teamwork.',
  ),
  _WordEntry(
    'clarity',
    'the quality of being easy to understand',
    'Clarity is more important than speed.',
  ),
  _WordEntry(
    'evidence',
    'information that supports an idea',
    'Good evidence makes your answer stronger.',
  ),
  _WordEntry(
    'example',
    'one thing that shows what you mean',
    'A personal example can make your point clear.',
  ),
  _WordEntry(
    'reason',
    'why something happens or is true',
    'The main reason is convenience.',
  ),
  _WordEntry(
    'impact',
    'a strong effect',
    'The impact of daily practice is visible over time.',
  ),
  _WordEntry(
    'balance',
    'a fair mix of different things',
    'Balance helps people avoid burnout.',
  ),
  _WordEntry(
    'growth',
    'the process of becoming better or stronger',
    'Growth often feels uncomfortable at first.',
  ),
  _WordEntry(
    'progress',
    'movement toward improvement',
    'Small progress is still progress.',
  ),
  _WordEntry(
    'purpose',
    'the reason for doing something',
    'A clear purpose keeps me motivated.',
  ),
  _WordEntry(
    'mindset',
    'a way of thinking',
    'A growth mindset makes mistakes less scary.',
  ),
  _WordEntry(
    'outcome',
    'the final result',
    'The outcome was better than I expected.',
  ),
  _WordEntry(
    'approach',
    'a way of doing something',
    'My approach is to practice a little every day.',
  ),
  _WordEntry(
    'context',
    'the situation around an idea',
    'Context helps listeners understand your point.',
  ),
  _WordEntry(
    'trend',
    'a general direction of change',
    'This trend shows how people use technology.',
  ),
  _WordEntry(
    'identity',
    'who someone is or how they see themselves',
    'Style can express identity.',
  ),
];

List<_WordEntry> get _easyWords => _baseWords;
List<_WordEntry> get _mediumWords => [
  ..._baseWords.skip(20),
  ..._baseWords.take(20),
];
List<_WordEntry> get _hardWords => [
  ..._baseWords.skip(40),
  ..._baseWords.take(40),
];
