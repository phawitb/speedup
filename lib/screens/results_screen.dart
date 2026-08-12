import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../camera_service.dart';
import '../models.dart';
import '../theme.dart';
import 'record_screen.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({
    super.key,
    required this.controller,
    required this.cameraService,
  });
  final AppController controller;
  final CameraService cameraService;
  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  int tab = 0;

  void _restart({required bool newTopic}) {
    widget.controller.resetSession(newTopic: newTopic);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => RecordScreen(
          controller: widget.controller,
          cameraService: widget.cameraService,
        ),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PaperBackground(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
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
                          side: const BorderSide(color: ink, width: 1.6),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          ['Overview', 'Transcript', 'Revised'][index],
                          maxLines: 1,
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
                  OverviewTab(result: widget.controller.result),
                  TranscriptTab(result: widget.controller.result),
                  RevisedTab(result: widget.controller.result),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 7, 12, 10),
              color: paper,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _restart(newTopic: false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ink,
                        minimumSize: const Size(0, 48),
                        side: const BorderSide(color: ink, width: 1.6),
                      ),
                      child: const Text('Try Again'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _restart(newTopic: true),
                      style: FilledButton.styleFrom(
                        backgroundColor: yellow,
                        foregroundColor: ink,
                        minimumSize: const Size(0, 48),
                        side: const BorderSide(color: ink, width: 1.6),
                      ),
                      child: const Text('New Topic'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key, required this.result});
  final AnalysisResult result;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Column(
            children: [
              Text(
                '${result.overallScore}',
                style: const TextStyle(
                  fontSize: 54,
                  height: .95,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text('out of 100'),
              const SizedBox(height: 4),
              const Text(
                'Great work! 👏',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const _SectionTitle('Detailed Scores'),
        const SizedBox(height: 10),
        ...result.categoryScores.entries.map(
          (entry) => _ScoreRow(label: entry.key, score: entry.value),
        ),
        const SizedBox(height: 16),
        const _SectionTitle('What You Did Well'),
        _BulletList(items: result.strengths, color: green),
        const SizedBox(height: 14),
        const _SectionTitle('Focus Next Time'),
        _BulletList(items: result.improvements, color: orange),
        const SizedBox(height: 14),
        const _SectionTitle('Filler Words'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: result.repeatedWords.entries
              .map(
                (entry) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: paperDeep,
                    border: Border.all(color: ink),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${entry.key}  ×${entry.value}'),
                ),
              )
              .toList(),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleLarge);
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({required this.label, required this.score});
  final String label;
  final int score;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('$score', style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 5),
        LinearProgressIndicator(
          value: score / 100,
          minHeight: 7,
          borderRadius: BorderRadius.circular(8),
          color: score >= 82
              ? green
              : score >= 79
              ? yellowDeep
              : orange,
          backgroundColor: paperDeep,
        ),
      ],
    ),
  );
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items, required this.color});
  final List<String> items;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    children: items
        .map(
          (item) => Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  color: color,
                  size: 19,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(item)),
              ],
            ),
          ),
        )
        .toList(),
  );
}

class TranscriptTab extends StatelessWidget {
  const TranscriptTab({super.key, required this.result});
  final AnalysisResult result;

  @override
  Widget build(BuildContext context) {
    final fullText = result.transcriptSentences
        .map((item) => item.original)
        .join(' ');
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _SectionTitle('Sentence Review')),
              IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: fullText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Transcript copied')),
                  );
                },
                icon: const Icon(Icons.copy_rounded),
              ),
            ],
          ),
          const Text('Review your speech one sentence at a time.'),
          const SizedBox(height: 12),
          ...result.transcriptSentences.asMap().entries.map(
            (entry) =>
                _SentenceCard(index: entry.key + 1, sentence: entry.value),
          ),
        ],
      ),
    );
  }
}

class _SentenceCard extends StatelessWidget {
  const _SentenceCard({required this.index, required this.sentence});
  final int index;
  final TranscriptSentence sentence;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 11),
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: paper,
      border: Border.all(color: ink, width: 1.5),
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [BoxShadow(color: ink, offset: Offset(2, 2))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: sentence.needsCorrection ? orange : green,
              foregroundColor: ink,
              child: Text(
                '$index',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                sentence.needsCorrection
                    ? 'Needs a small fix'
                    : 'Sounds natural',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(sentence.original, style: const TextStyle(fontSize: 18)),
        if (sentence.needsCorrection) ...[
          const Divider(height: 20),
          const Text(
            'Suggested correction',
            style: TextStyle(
              color: Color(0xFF2AA96B),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sentence.correction!,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          if (sentence.note != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                sentence.note!,
                style: const TextStyle(color: inkSoft),
              ),
            ),
        ],
      ],
    ),
  );
}

class RevisedTab extends StatelessWidget {
  const RevisedTab({super.key, required this.result});
  final AnalysisResult result;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('A Smoother Version'),
        const SizedBox(height: 4),
        const Text(
          'This version keeps your ideas while improving flow, transitions, and word choice.',
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: paper,
            border: Border.all(color: ink, width: 1.7),
            borderRadius: BorderRadius.circular(13),
            boxShadow: const [BoxShadow(color: ink, offset: Offset(3, 3))],
          ),
          child: Text(
            result.revisedVersion,
            style: const TextStyle(fontSize: 19, height: 1.45),
          ),
        ),
        const SizedBox(height: 16),
        const _SectionTitle('What Changed'),
        _BulletList(items: result.revisedChanges, color: purple),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: result.revisedVersion));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Revised version copied')),
              );
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy Revised Version'),
            style: OutlinedButton.styleFrom(
              foregroundColor: ink,
              side: const BorderSide(color: ink, width: 1.5),
              minimumSize: const Size(0, 48),
            ),
          ),
        ),
      ],
    ),
  );
}
