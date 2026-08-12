import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../audio_extraction_service.dart';
import '../camera_service.dart';
import '../direct_video_recording_service.dart';
import '../theme.dart';
import '../transcription_service.dart';
import '../widgets/common.dart';
import 'processing_screen.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({
    super.key,
    required this.controller,
    required this.cameraService,
  });
  final AppController controller;
  final CameraService cameraService;
  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen>
    with WidgetsBindingObserver {
  Timer? timer;
  int elapsed = 0;
  bool finishing = false;
  bool preparingVideo = false;
  bool showGuide = false;
  bool captureReady = false;
  bool startingCapture = true;
  String? captureError;
  String? finishError;
  late final DirectVideoRecordingService videoRecording;

  int get total => widget.controller.settings.durationSeconds;

  @override
  void initState() {
    super.initState();
    videoRecording = DirectVideoRecordingService(
      cameraService: widget.cameraService,
      topic: widget.controller.session.topic,
      day: widget.controller.streak.currentDay,
      durationSeconds: widget.controller.settings.durationSeconds,
      avatarStyle: widget.controller.avatarStyle,
    );
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startCapture());
  }

  Future<void> _startCapture() async {
    if (!mounted) return;
    setState(() {
      startingCapture = true;
      captureError = null;
      captureReady = false;
    });
    await videoRecording.start();
    if (!mounted) return;
    if (!videoRecording.isRecording) {
      setState(() {
        startingCapture = false;
        captureError = videoRecording.error ?? 'Could not start the camera.';
      });
      return;
    }
    setState(() {
      captureReady = true;
      startingCapture = false;
    });
    _startTimer();
  }

  void _startTimer() {
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || finishing) return;
      setState(() => elapsed++);
      widget.controller.setElapsed(elapsed);
      if (elapsed >= total) _finish(timedOut: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) timer?.cancel();
    if (state == AppLifecycleState.resumed && captureReady && !finishing) {
      _startTimer();
    }
  }

  Future<void> _finish({bool timedOut = false}) async {
    if (finishing) return;
    timer?.cancel();
    setState(() {
      finishing = true;
      preparingVideo = false;
      finishError = null;
    });
    try {
      await videoRecording.stop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        finishing = false;
        preparingVideo = false;
        finishError = error.toString().replaceFirst('Exception: ', '');
      });
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => CompletionSheet(
        controller: widget.controller,
        cameraService: widget.cameraService,
        videoRecording: videoRecording,
        celebrate: timedOut,
      ),
    );
    if (mounted) {
      setState(() {
        finishing = false;
        preparingVideo = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    if (!finishing &&
        (videoRecording.isRecording ||
            videoRecording.pendingVideoPath != null)) {
      unawaited(videoRecording.discard());
    }
    videoRecording.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remainingRatio = ((total - elapsed) / total).clamp(0.0, 1.0);
    final progressColor = remainingRatio <= .15
        ? const Color(0xFFE83C31)
        : remainingRatio <= .35
        ? const Color(0xFFF39A32)
        : purple;
    return Scaffold(
      body: Stack(
        children: [
          PaperBackground(
            child: SafeArea(
              bottom: false,
              child: LayoutBuilder(
                builder: (context, constraints) => Column(
                  children: [
                    SizedBox(
                      height: constraints.maxHeight / 2,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 42, 18, 8),
                            child: Row(
                              children: [
                                Text(
                                  'Day ${widget.controller.streak.currentDay} 🔥',
                                  style: const TextStyle(
                                    fontSize: 25,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                const _PulsingRecBadge(),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 34),
                            child: _RecordingTopicText(
                              topic: widget.controller.session.topic,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _time((total - elapsed).clamp(0, total)),
                            style: const TextStyle(
                              fontSize: 53,
                              height: 1,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 44),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: remainingRatio,
                                minHeight: 10,
                                backgroundColor: const Color(0xFFDED5E8),
                                color: progressColor,
                              ),
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: constraints.maxHeight / 2,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CoachPreview(
                              cameraService: widget.cameraService,
                              recording: true,
                              avatarStyle: widget.controller.avatarStyle,
                            ),
                          ),
                          if (startingCapture || captureError != null)
                            Positioned.fill(
                              child: ColoredBox(
                                color: Colors.black.withValues(alpha: .62),
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(28),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (startingCapture)
                                          const CircularProgressIndicator(
                                            color: yellow,
                                          )
                                        else ...[
                                          const Icon(
                                            Icons.videocam_off_rounded,
                                            color: Colors.white,
                                            size: 42,
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            captureError!,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(height: 14),
                                          FilledButton.icon(
                                            onPressed: _startCapture,
                                            icon: const Icon(
                                              Icons.refresh_rounded,
                                            ),
                                            label: const Text('Retry Camera'),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: yellow,
                                              foregroundColor: ink,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            bottom:
                                MediaQuery.viewPaddingOf(context).bottom + 14,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: InkWell(
                                onTap: captureReady ? _finish : null,
                                borderRadius: BorderRadius.circular(50),
                                child: Container(
                                  width: 76,
                                  height: 76,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE83C31),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 4,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.stop_rounded,
                                    color: Colors.white,
                                    size: 35,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 18,
                            bottom:
                                MediaQuery.viewPaddingOf(context).bottom + 22,
                            child: FloatingActionButton.small(
                              heroTag: 'guide',
                              onPressed: () =>
                                  setState(() => showGuide = !showGuide),
                              backgroundColor: showGuide
                                  ? yellow
                                  : Colors.white,
                              foregroundColor: ink,
                              child: Icon(
                                showGuide
                                    ? Icons.close_rounded
                                    : Icons.lightbulb_outline_rounded,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (showGuide)
            Positioned(
              left: 14,
              right: 14,
              bottom: MediaQuery.viewPaddingOf(context).bottom + 92,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .58,
                ),
                child: SingleChildScrollView(
                  child: _SpeakingGuide(topic: widget.controller.session.topic),
                ),
              ),
            ),
          if (preparingVideo)
            const Positioned.fill(child: _PreparingVideoOverlay()),
          if (finishError != null)
            Positioned.fill(
              child: _VideoErrorOverlay(
                message: finishError!,
                onBack: () => Navigator.maybePop(context),
              ),
            ),
        ],
      ),
    );
  }
}

class _PreparingVideoOverlay extends StatefulWidget {
  const _PreparingVideoOverlay();

  @override
  State<_PreparingVideoOverlay> createState() => _PreparingVideoOverlayState();
}

class _RecordingTopicText extends StatelessWidget {
  const _RecordingTopicText({required this.topic});

  final String topic;

  @override
  Widget build(BuildContext context) {
    final lines = topic
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length >= 3) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            lines[0],
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 24,
              color: ink,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            lines[1],
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: inkSoft, height: 1.05),
          ),
          Text(
            lines[2],
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: inkSoft,
              height: 1.05,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }
    return Text(
      topic,
      textAlign: TextAlign.center,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 20,
        color: ink,
        fontWeight: FontWeight.w600,
        height: 1.12,
      ),
    );
  }
}

class _PreparingVideoOverlayState extends State<_PreparingVideoOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: ink.withValues(alpha: .84),
    child: SafeArea(
      child: Center(
        child: Container(
          width: 286,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
          decoration: BoxDecoration(
            color: paper,
            border: Border.all(color: ink, width: 2),
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 26,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final bob = math.sin(controller.value * math.pi * 2) * 6;
                  return Transform.translate(
                    offset: Offset(0, bob),
                    child: Icon(
                      Icons.movie_filter_rounded,
                      color: Color.lerp(purple, yellowDeep, controller.value),
                      size: 56,
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              const Text(
                'Preparing video',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Building your final clip with the timer, topic, and avatar.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: inkSoft),
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: SizedBox(
                  height: 12,
                  child: AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) => LinearProgressIndicator(
                      value: .18 + controller.value * .70,
                      backgroundColor: const Color(0xFFE9E3D4),
                      color: Color.lerp(yellow, green, controller.value),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _VideoErrorOverlay extends StatelessWidget {
  const _VideoErrorOverlay({required this.message, required this.onBack});

  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: ink.withValues(alpha: .9),
    child: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: yellow, size: 55),
              const SizedBox(height: 14),
              const Text(
                'Could not prepare the video',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.home_rounded),
                label: const Text('Back to Home'),
                style: FilledButton.styleFrom(
                  backgroundColor: yellow,
                  foregroundColor: ink,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PulsingRecBadge extends StatefulWidget {
  const _PulsingRecBadge();

  @override
  State<_PulsingRecBadge> createState() => _PulsingRecBadgeState();
}

class _PulsingRecBadgeState extends State<_PulsingRecBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final Animation<double> pulse;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    pulse = CurvedAnimation(parent: controller, curve: Curves.easeInOutCubic);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: pulse,
    builder: (context, child) => Transform.scale(
      scale: .98 + pulse.value * .035,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Color.lerp(Colors.white, const Color(0xFFFFE6E3), pulse.value),
          border: Border.all(
            color: Color.lerp(
              const Color(0xFFD4C8B9),
              const Color(0xFFE83C31),
              pulse.value,
            )!,
            width: 1.4,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(
                0xFFE83C31,
              ).withValues(alpha: .10 + pulse.value * .24),
              blurRadius: 5 + pulse.value * 11,
              spreadRadius: pulse.value * 2,
              offset: Offset(0, 2 + pulse.value * 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: const Color(0xFFE83C31),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(
                      0xFFE83C31,
                    ).withValues(alpha: .35 + pulse.value * .45),
                    blurRadius: 3 + pulse.value * 8,
                    spreadRadius: pulse.value * 2,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            const Text(
              'REC',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SpeakingGuide extends StatelessWidget {
  const _SpeakingGuide({required this.topic});
  final String topic;

  @override
  Widget build(BuildContext context) {
    final guide = _guideFor(topic);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: paper.withValues(alpha: .96),
        border: Border.all(color: ink, width: 1.7),
        borderRadius: BorderRadius.circular(13),
        boxShadow: const [BoxShadow(color: ink, offset: Offset(3, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_rounded, color: yellowDeep, size: 21),
              const SizedBox(width: 7),
              Text(
                'Speaking Guide',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...guide.ideas.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('•  $item'),
            ),
          ),
          const Divider(height: 15),
          Text(
            'Category words',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 5),
          ...guide.words.map(
            (word) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: const Color(0xFFE5DCCB),
                    width: 1.1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      word.word,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ink,
                        fontSize: 19,
                        height: 1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      word.definition,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: inkSoft,
                        fontSize: 12,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      word.example,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: inkSoft,
                        fontSize: 12,
                        height: 1.12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 15),
          Text(
            'Useful language',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: guide.phrases
                .map(
                  (phrase) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: yellow.withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(phrase, style: const TextStyle(fontSize: 13)),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  static _GuideContent _guideFor(String topic) {
    if (topic.contains('fictional world')) {
      return const _GuideContent(
        ideas: [
          'Name the world and describe it',
          'Explain what you would do there',
          'Say why it suits you',
        ],
        phrases: [
          'If I could…',
          'What appeals to me is…',
          'I would be fascinated by…',
        ],
        words: [
          _CategoryWord(
            'immersive',
            'deeply engaging and realistic',
            'The world feels immersive because every detail has meaning.',
          ),
          _CategoryWord(
            'adventure',
            'an exciting or unusual experience',
            'I would choose this world because it is full of adventure.',
          ),
          _CategoryWord(
            'belong',
            'to feel accepted in a place or group',
            'I think I would belong there because the people are brave.',
          ),
        ],
      );
    }
    if (topic.contains('habit')) {
      return const _GuideContent(
        ideas: [
          'Describe the habit',
          'Explain how you started',
          'Share the impact on your life',
        ],
        phrases: ['I began by…', 'Over time…', 'The biggest change was…'],
        words: [
          _CategoryWord(
            'consistent',
            'happening regularly in a reliable way',
            'Being consistent helped me improve little by little.',
          ),
          _CategoryWord(
            'routine',
            'a regular way of doing things',
            'This routine makes my day feel more organized.',
          ),
          _CategoryWord(
            'impact',
            'a strong effect or result',
            'The biggest impact is that I feel more confident.',
          ),
        ],
      );
    }
    if (topic.contains('skill')) {
      return const _GuideContent(
        ideas: [
          'Name the skill',
          'Explain how you would use it',
          'Describe who it could help',
        ],
        phrases: [
          'I would choose…',
          'This would allow me to…',
          'In the long run…',
        ],
        words: [
          _CategoryWord(
            'master',
            'to become highly skilled at something',
            'I would love to master this skill quickly.',
          ),
          _CategoryWord(
            'practical',
            'useful in real situations',
            'It is practical because I could use it every day.',
          ),
          _CategoryWord(
            'opportunity',
            'a chance to do something useful',
            'This skill would create more opportunities for me.',
          ),
        ],
      );
    }
    return const _GuideContent(
      ideas: [
        'Describe what the place looks like',
        'Mention sounds, smells, or feelings',
        'Explain why it matters to you',
      ],
      phrases: [
        'Whenever I am there…',
        'What makes it special is…',
        'It gives me a sense of…',
      ],
      words: [
        _CategoryWord(
          'peaceful',
          'calm and quiet',
          'This place feels peaceful even when I am stressed.',
        ),
        _CategoryWord(
          'cozy',
          'warm, comfortable, and relaxing',
          'The cozy atmosphere helps me relax.',
        ),
        _CategoryWord(
          'refreshing',
          'making you feel new energy',
          'The fresh air is refreshing and clears my mind.',
        ),
      ],
    );
  }
}

class _GuideContent {
  const _GuideContent({
    required this.ideas,
    required this.phrases,
    required this.words,
  });
  final List<String> ideas;
  final List<String> phrases;
  final List<_CategoryWord> words;
}

class _CategoryWord {
  const _CategoryWord(this.word, this.definition, this.example);
  final String word;
  final String definition;
  final String example;
}

String _time(int seconds) =>
    '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

class CompletionSheet extends StatefulWidget {
  const CompletionSheet({
    super.key,
    required this.controller,
    required this.cameraService,
    required this.videoRecording,
    this.celebrate = false,
  });
  final AppController controller;
  final CameraService cameraService;
  final DirectVideoRecordingService videoRecording;
  final bool celebrate;

  @override
  State<CompletionSheet> createState() => _CompletionSheetState();
}

class _CompletionSheetState extends State<CompletionSheet>
    with SingleTickerProviderStateMixin {
  bool saving = false;
  bool saved = false;
  bool preparing = false;
  bool videoDecisionMade = false;
  String? savedWavPath;
  TranscriptionResult? savedTranscription;
  final _audioExtractor = AudioExtractionService();
  final _transcription = const TranscriptionService();
  late final AnimationController celebrationController;

  @override
  void initState() {
    super.initState();
    celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.celebrate) celebrationController.forward();
  }

  @override
  void dispose() {
    celebrationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (saving || saved) return;
    setState(() {
      saving = true;
      preparing = true;
    });
    try {
      final transcript = await _transcribeForSave();
      await widget.videoRecording.save(
        transcriptSegments: transcript.segments
            .where((segment) => segment.text.trim().isNotEmpty)
            .map(
              (segment) => {
                'text': segment.text,
                'startMs': segment.startMs,
                'endMs': segment.endMs,
              },
            )
            .toList(),
      );
      if (!mounted) return;
      setState(() {
        saving = false;
        preparing = false;
        saved = true;
        videoDecisionMade = true;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Video saved to Photos')));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        saving = false;
        preparing = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save video: $error')));
    }
  }

  Future<void> _skipSave() async {
    if (saving) return;
    setState(() => videoDecisionMade = true);
  }

  @override
  Widget build(BuildContext context) => BottomSheetShell(
    child: Stack(
      children: [
        if (!preparing)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .70,
            ),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const Text('🎉', style: TextStyle(fontSize: 42)),
                  const Text(
                    'Well done!',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'You spoke for ${_time(widget.controller.session.elapsedSeconds)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child: videoDecisionMade
                        ? _ActionTile(
                            key: const ValueKey('analyze'),
                            icon: Icons.psychology_rounded,
                            color: purple,
                            title: 'Analyze My Speech',
                            subtitle: saved
                                ? 'Video saved — ready for your feedback'
                                : 'Get a transcript, corrections, and feedback',
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ProcessingScreen(
                                    controller: widget.controller,
                                    cameraService: widget.cameraService,
                                    videoRecording: widget.videoRecording,
                                    initialWavPath: savedWavPath,
                                    initialTranscription: savedTranscription,
                                  ),
                                ),
                              );
                            },
                          )
                        : Column(
                            key: const ValueKey('video-choice'),
                            children: [
                              const Text(
                                'Would you like to save this video?',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Saving exports the final clip. Skipping lets you analyze right away.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, color: inkSoft),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Tooltip(
                                    message: 'Save Video',
                                    child: InkWell(
                                      onTap: _save,
                                      customBorder: const CircleBorder(),
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 250,
                                        ),
                                        width: 64,
                                        height: 64,
                                        decoration: BoxDecoration(
                                          color: yellow,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: ink,
                                            width: 2,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: ink,
                                              offset: Offset(3, 3),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.download_rounded,
                                          color: ink,
                                          size: 30,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 22),
                                  TextButton(
                                    onPressed: _skipSave,
                                    style: TextButton.styleFrom(
                                      foregroundColor: inkSoft,
                                    ),
                                    child: const Text(
                                      "Don't Save",
                                      style: TextStyle(fontSize: 17),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        if (preparing)
          SizedBox(
            height: math.min(MediaQuery.sizeOf(context).height * .54, 480),
            child: _SheetPreparingOverlay(
              progress: widget.videoRecording.exportProgress,
              stage: widget.videoRecording.exportStage,
            ),
          ),
        if (!preparing && widget.celebrate)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: celebrationController,
                builder: (context, _) => CustomPaint(
                  painter: _CelebrationPainter(celebrationController.value),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Future<TranscriptionResult> _transcribeForSave() async {
    final existing = savedTranscription;
    if (existing != null) return existing;
    final videoPath = widget.videoRecording.pendingVideoPath;
    if (videoPath == null) {
      throw StateError('No recorded video is available.');
    }
    widget.videoRecording.exportStage.value = 'Creating transcript';
    widget.videoRecording.exportProgress.value = .08;
    savedWavPath ??= await _audioExtractor.extractWav(videoPath);
    widget.videoRecording.exportProgress.value = .18;
    savedTranscription = await _transcription.transcribe(savedWavPath!);
    widget.videoRecording.exportProgress.value = .32;
    return savedTranscription!;
  }
}

class _SheetPreparingOverlay extends StatefulWidget {
  const _SheetPreparingOverlay({required this.progress, required this.stage});

  final ValueListenable<double> progress;
  final ValueListenable<String> stage;

  @override
  State<_SheetPreparingOverlay> createState() => _SheetPreparingOverlayState();
}

class _SheetPreparingOverlayState extends State<_SheetPreparingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: paper,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
    ),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) => Transform.scale(
                scale: .94 + controller.value * .08,
                child: const Icon(
                  Icons.video_settings_rounded,
                  size: 54,
                  color: purple,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<String>(
              valueListenable: widget.stage,
              builder: (context, stage, _) => Text(
                stage,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Almost ready. Please keep the app open.',
              textAlign: TextAlign.center,
              style: TextStyle(color: inkSoft, fontSize: 14),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 220,
              child: ValueListenableBuilder<double>(
                valueListenable: widget.progress,
                builder: (context, progress, _) => Column(
                  children: [
                    LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(12),
                      backgroundColor: const Color(0xFFE9E3D4),
                      color: Color.lerp(yellow, green, progress),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(progress * 100).round().clamp(0, 100)}%',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CelebrationPainter extends CustomPainter {
  const _CelebrationPainter(this.progress);

  final double progress;
  static const colors = [yellow, purple, green, Color(0xFFE83C31)];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var burst = 0; burst < 3; burst++) {
      final local = ((progress * 1.35) - burst * .18).clamp(0.0, 1.0);
      if (local == 0 || local == 1) continue;
      final center = Offset(
        size.width * (.22 + burst * .28),
        size.height * (.22 + (burst.isOdd ? .12 : 0)),
      );
      for (var ray = 0; ray < 12; ray++) {
        final angle = (math.pi * 2 / 12) * ray + burst * .35;
        final distance = 18 + 70 * Curves.easeOut.transform(local);
        final fade = (1 - local).clamp(0.0, 1.0);
        paint
          ..color = colors[(ray + burst) % colors.length].withValues(
            alpha: fade,
          )
          ..strokeWidth = 4;
        final end =
            center + Offset(math.cos(angle), math.sin(angle)) * distance;
        final start =
            center + Offset(math.cos(angle), math.sin(angle)) * (distance - 10);
        canvas.drawLine(start, end, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CelebrationPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: color.withValues(alpha: .04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: .32)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color,
          foregroundColor: Colors.white,
          child: Icon(icon),
        ),
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w700, color: color),
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
        trailing: Icon(Icons.chevron_right_rounded, color: color),
      ),
    ),
  );
}
