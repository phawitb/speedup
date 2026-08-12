import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../camera_service.dart';
import '../models.dart';
import '../theme.dart';
import 'record_screen.dart';
import 'results_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({
    super.key,
    required this.controller,
    required this.cameraService,
  });
  final AppController controller;
  final CameraService cameraService;

  void _home(BuildContext context) {
    controller.resetSession();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) =>
            RecordScreen(controller: controller, cameraService: cameraService),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PaperBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 18, 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => _home(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Text(
                      'Practice History',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.headlineMedium?.copyWith(fontSize: 28),
                    ),
                  ),
                ],
              ),
            ),
            _StreakCard(day: controller.streak.currentDay),
            const SizedBox(height: 14),
            Expanded(
              child: controller.history.isEmpty
                  ? const _EmptyHistory()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
                      itemCount: controller.history.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 11),
                      itemBuilder: (context, index) => _HistoryCard(
                        item: controller.history[index],
                        number: controller.history.length - index,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => HistoryDetailScreen(
                              item: controller.history[index],
                              result: controller.history[index].result,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.day});

  final int day;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
    decoration: BoxDecoration(
      color: yellow,
      border: Border.all(color: ink, width: 1.7),
      borderRadius: BorderRadius.circular(14),
      boxShadow: const [BoxShadow(color: ink, offset: Offset(3, 3))],
    ),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: paper,
            shape: BoxShape.circle,
            border: Border.all(color: ink, width: 1.5),
          ),
          child: const Text('🔥', style: TextStyle(fontSize: 25)),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Day Streak',
                style: TextStyle(fontSize: 16, color: inkSoft),
              ),
              Text(
                'Day $day',
                style: const TextStyle(
                  fontSize: 27,
                  height: 1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const Text(
          'Keep it going!',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.history_rounded, size: 70, color: inkSoft),
          const SizedBox(height: 14),
          Text(
            'No practice sessions yet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text(
            'Complete an AI analysis and your progress will appear here.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.item,
    required this.number,
    required this.onTap,
  });
  final PracticeHistoryItem item;
  final int number;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(13),
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      decoration: BoxDecoration(
        color: paper,
        border: Border.all(color: ink, width: 1.6),
        borderRadius: BorderRadius.circular(13),
        boxShadow: const [BoxShadow(color: ink, offset: Offset(3, 3))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: yellow,
              shape: BoxShape.circle,
              border: Border.all(color: ink, width: 1.5),
            ),
            child: Text(
              '${item.score}',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.topic,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '${_date(item.date)}  •  ${_duration(item.durationSeconds)}',
                  style: const TextStyle(color: inkSoft),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Text('#$number', style: const TextStyle(color: inkSoft)),
              const SizedBox(height: 8),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ],
      ),
    ),
  );

  static String _date(DateTime date) =>
      '${_months[date.month - 1]} ${date.day}, ${date.year}';
  static String _duration(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

class HistoryDetailScreen extends StatefulWidget {
  const HistoryDetailScreen({
    super.key,
    required this.item,
    required this.result,
  });
  final PracticeHistoryItem item;
  final AnalysisResult result;
  @override
  State<HistoryDetailScreen> createState() => _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  int tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PaperBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 14, 5),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Past Analysis',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          widget.item.topic,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: inkSoft),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: yellow,
                      shape: BoxShape.circle,
                      border: Border.all(color: ink),
                    ),
                    child: Text(
                      '${widget.item.score}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: List.generate(
                  3,
                  (index) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: OutlinedButton(
                        onPressed: () => setState(() => tab = index),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: tab == index ? yellow : paper,
                          foregroundColor: ink,
                          side: const BorderSide(color: ink),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                        child: Text(
                          ['Overview', 'Transcript', 'Revised'][index],
                          maxLines: 1,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: tab,
                children: [
                  OverviewTab(result: widget.result),
                  TranscriptTab(result: widget.result),
                  RevisedTab(result: widget.result),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
