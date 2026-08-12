import 'dart:io';

import 'package:flutter/material.dart';

import '../analysis_api.dart';
import '../app_controller.dart';
import '../audio_extraction_service.dart';
import '../camera_service.dart';
import '../direct_video_recording_service.dart';
import '../theme.dart';
import '../transcription_service.dart';
import 'record_screen.dart';
import 'results_screen.dart';

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({
    super.key,
    required this.controller,
    required this.cameraService,
    required this.videoRecording,
    this.initialWavPath,
    this.initialTranscription,
  });
  final AppController controller;
  final CameraService cameraService;
  final DirectVideoRecordingService videoRecording;
  final String? initialWavPath;
  final TranscriptionResult? initialTranscription;

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  final _audioExtractor = AudioExtractionService();
  final _transcription = const TranscriptionService();
  final _analysisApi = AnalysisApi();
  int step = 0;
  String? error;
  String? wavPath;
  TranscriptionResult? transcription;
  bool running = false;

  @override
  void initState() {
    super.initState();
    wavPath = widget.initialWavPath;
    transcription = widget.initialTranscription;
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (running) return;
    setState(() {
      running = true;
      error = null;
    });
    try {
      if (transcription == null) {
        setState(() => step = 0);
        wavPath ??= await _audioExtractor.extractWav(
          widget.videoRecording.pendingVideoPath ??
              (throw StateError(
                'No recorded video is available for transcription.',
              )),
        );
        if (!mounted) return;
        setState(() => step = 1);
        transcription = await _transcription.transcribe(wavPath!);
      }
      if (!mounted) return;
      setState(() => step = 2);
      final result = await _analysisApi.analyze(
        topic: widget.controller.session.topic,
        difficulty: widget.controller.settings.difficulty,
        durationSeconds: widget.controller.session.elapsedSeconds,
        transcription: transcription!,
      );
      widget.controller.setAnalysisResult(result);
      await widget.controller.completePractice();
      await _cleanup();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultsScreen(
            controller: widget.controller,
            cameraService: widget.cameraService,
          ),
        ),
      );
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        running = false;
        error = _friendlyError(exception);
      });
    }
  }

  String _friendlyError(Object exception) {
    final message = exception.toString().replaceFirst('Exception: ', '');
    if (message.contains('audio track')) {
      return 'This recording has no microphone audio. On iOS Simulator, allow microphone access and record again. On a device, check the microphone permission.';
    }
    return message;
  }

  Future<void> _cleanup() async {
    final path = wavPath;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
      wavPath = null;
    }
    await widget.videoRecording.discard();
  }

  @override
  void dispose() {
    _analysisApi.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PaperBackground(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🧠', style: TextStyle(fontSize: 77)),
              const SizedBox(height: 28),
              Text(
                error == null ? 'Analyzing your speech...' : 'Analysis paused',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 34),
              _Step(label: 'Preparing recorded audio', state: _stateFor(0)),
              _Step(
                label: 'Creating an on-device transcript',
                state: _stateFor(1),
              ),
              _Step(
                label: 'Reviewing grammar and delivery',
                state: _stateFor(2),
              ),
              const SizedBox(height: 30),
              if (error == null) ...[
                LinearProgressIndicator(
                  value: step == 2 ? null : (step + .35) / 3,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(10),
                  backgroundColor: const Color(0xFFE4DDD1),
                  color: purple,
                ),
                const SizedBox(height: 14),
                Text(
                  step == 1
                      ? 'The speech model is downloaded once, then stays on this device.'
                      : 'Your microphone audio stays on this device.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE8E4),
                    border: Border.all(color: ink),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(error!, textAlign: TextAlign.center),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _run,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try Again'),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await _cleanup();
                    if (context.mounted) {
                      widget.controller.resetSession();
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
                  },
                  child: const Text('Back to Record'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  int _stateFor(int index) {
    if (error != null && index == step) return 3;
    if (index < step) return 2;
    if (index == step) return 1;
    return 0;
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.state});
  final String label;
  final int state;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        SizedBox(
          width: 28,
          child: state == 2
              ? const Icon(Icons.check_circle_outline_rounded, color: green)
              : state == 3
              ? const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFE83C31),
                )
              : state == 1
              ? const SizedBox(
                  width: 21,
                  height: 21,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: green,
                  ),
                )
              : const Icon(
                  Icons.circle_outlined,
                  color: Color(0xFFAAA399),
                  size: 21,
                ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: state == 1 ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}
