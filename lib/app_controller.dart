import 'dart:convert';

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

  static Future<AppController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final controller = AppController._(prefs);
    controller.settings = PracticeSettings(
      difficulty: Difficulty.values[prefs.getInt('difficulty') ?? 0],
      topicCategory: prefs.getString('category') ?? 'Random',
      durationSeconds: prefs.getInt('duration') ?? 60,
      filter: prefs.getString('filter') ?? 'None',
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
      _prefs.setString('filter', value.filter),
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
      final index = (topics.indexOf(topic) + 1) % topics.length;
      topic = topics[index];
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
      var index = topics.indexOf(original);
      for (var turn = 0; turn < 9; turn++) {
        index = (index + 1 + (turn % (topics.length - 1))) % topics.length;
        session = PracticeSession(topic: topics[index]);
        notifyListeners();
        await Future<void>.delayed(Duration(milliseconds: 75 + turn * 10));
      }
      if (session.topic == original) {
        session = PracticeSession(topic: topics[(index + 1) % topics.length]);
        notifyListeners();
      }
      await _prefs.setString('topic', session.topic);
    } finally {
      isRandomizing = false;
      notifyListeners();
    }
  }

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
