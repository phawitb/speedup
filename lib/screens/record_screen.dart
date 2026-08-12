import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../camera_service.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'recording_screen.dart';
import 'history_screen.dart';

class RecordScreen extends StatefulWidget {
  const RecordScreen({
    super.key,
    required this.controller,
    required this.cameraService,
  });
  final AppController controller;
  final CameraService cameraService;
  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  Future<void> _openAvatarCustomizer() async {
    final style = await showModalBottomSheet<AvatarStyle>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AvatarCustomizer(initial: widget.controller.avatarStyle),
    );
    if (style != null) await widget.controller.updateAvatarStyle(style);
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HistoryScreen(
          controller: widget.controller,
          cameraService: widget.cameraService,
        ),
      ),
    );
  }

  Future<void> _pickDifficulty() async {
    final selected = await showModalBottomSheet<Difficulty>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickPicker<Difficulty>(
        title: 'Difficulty',
        values: Difficulty.values,
        selected: widget.controller.settings.difficulty,
        label: (value) => ['Random', 'Easy', 'Medium', 'Hard'][value.index],
      ),
    );
    if (selected != null) {
      await widget.controller.updateSettings(
        widget.controller.settings.copyWith(difficulty: selected),
      );
    }
  }

  Future<void> _pickCategory() async {
    const values = ['Random', 'General', 'Tech', 'Finance', 'IELTS', 'Gen Z'];
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickPicker<String>(
        title: 'Topic Category',
        values: values,
        selected: widget.controller.settings.topicCategory,
        label: (value) => value,
      ),
    );
    if (selected != null) {
      await widget.controller.updateSettings(
        widget.controller.settings.copyWith(topicCategory: selected),
      );
    }
  }

  Future<void> _pickDuration() async {
    const values = [30, 45, 60, 90, 120];
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickPicker<int>(
        title: 'Duration',
        values: values,
        selected: widget.controller.settings.durationSeconds,
        label: _durationLabel,
      ),
    );
    if (selected != null) {
      await widget.controller.updateSettings(
        widget.controller.settings.copyWith(durationSeconds: selected),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.controller, widget.cameraService]),
    builder: (context, _) {
      final controller = widget.controller;
      return Scaffold(
        body: PaperBackground(
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
                          padding: const EdgeInsets.fromLTRB(18, 9, 18, 4),
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: 'Practice History',
                                onPressed: _openHistory,
                                icon: const Icon(
                                  Icons.history_rounded,
                                  size: 26,
                                ),
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints.tightFor(
                                  width: 36,
                                  height: 36,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'Day ${controller.streak.currentDay} 🔥',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Center(
                            child: TopicCard(
                              topic: controller.session.topic,
                              onRandom: controller.randomizeTopic,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 5, 12, 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: _SettingButton(
                                  icon: Icons.speed_rounded,
                                  label: [
                                    'Random',
                                    'Easy',
                                    'Medium',
                                    'Hard',
                                  ][controller.settings.difficulty.index],
                                  onTap: _pickDifficulty,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _SettingButton(
                                  icon: Icons.timer_outlined,
                                  label: _durationLabel(
                                    controller.settings.durationSeconds,
                                  ),
                                  onTap: _pickDuration,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _SettingButton(
                                  icon: Icons.tag_rounded,
                                  label: controller.settings.topicCategory,
                                  onTap: _pickCategory,
                                ),
                              ),
                            ],
                          ),
                        ),
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
                            avatarStyle: controller.avatarStyle,
                          ),
                        ),
                        Positioned(
                          left: 18,
                          right: 18,
                          bottom: 16,
                          child: Row(
                            children: [
                              _RoundAction(
                                icon: widget.cameraService.isEnabled
                                    ? Icons.palette_outlined
                                    : Icons.palette_outlined,
                                label: 'Customize',
                                onTap: _openAvatarCustomizer,
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                child: PurpleButton(
                                  label: 'START',
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => RecordingScreen(
                                        controller: controller,
                                        cameraService: widget.cameraService,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 18),
                              _RoundAction(
                                icon: widget.cameraService.isEnabled
                                    ? Icons.videocam_rounded
                                    : Icons.face_rounded,
                                label: widget.cameraService.isEnabled
                                    ? 'Camera'
                                    : 'Avatar',
                                onTap: widget.cameraService.toggle,
                              ),
                            ],
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
      );
    },
  );
}

class _SettingButton extends StatelessWidget {
  const _SettingButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 17),
    label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    style: OutlinedButton.styleFrom(
      foregroundColor: ink,
      backgroundColor: paper,
      side: const BorderSide(color: ink, width: 1.5),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

class _QuickPicker<T> extends StatelessWidget {
  const _QuickPicker({
    required this.title,
    required this.values,
    required this.selected,
    required this.label,
  });
  final String title;
  final List<T> values;
  final T selected;
  final String Function(T) label;
  @override
  Widget build(BuildContext context) => BottomSheetShell(
    title: title,
    child: Wrap(
      spacing: 9,
      runSpacing: 9,
      alignment: WrapAlignment.center,
      children: values
          .map(
            (value) => ChoiceChip(
              label: Text(label(value)),
              selected: value == selected,
              onSelected: (_) => Navigator.pop(context, value),
            ),
          )
          .toList(),
    ),
  );
}

String _durationLabel(int seconds) => seconds < 60
    ? '00:${seconds.toString().padLeft(2, '0')}'
    : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(40),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 47,
          height: 47,
          decoration: const BoxDecoration(
            color: Color(0xD922211F),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key, required this.initial});
  final PracticeSettings initial;
  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late PracticeSettings value = widget.initial;
  @override
  Widget build(BuildContext context) => BottomSheetShell(
    title: 'Practice Settings',
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .72,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title('Difficulty'),
            ChoiceChipRow(
              values: const ['Random', 'Easy', 'Medium', 'Hard'],
              selected: _difficulty(value.difficulty),
              onSelected: (v) => setState(
                () => value = value.copyWith(
                  difficulty: Difficulty
                      .values[['Random', 'Easy', 'Medium', 'Hard'].indexOf(v)],
                ),
              ),
            ),
            _title('Topic Category'),
            ChoiceChipRow(
              values: const [
                'Random',
                'General',
                'Tech',
                'Finance',
                'Roast',
                'Pitch',
                'IELTS',
                'Gen Z',
              ],
              selected: value.topicCategory,
              onSelected: (v) =>
                  setState(() => value = value.copyWith(topicCategory: v)),
            ),
            _title('Duration'),
            ChoiceChipRow(
              values: const ['30 sec', '45 sec', '1 min', '1.5 min', '2 min'],
              selected: _durationChoice(value.durationSeconds),
              onSelected: (v) => setState(
                () => value = value.copyWith(
                  durationSeconds: const {
                    '30 sec': 30,
                    '45 sec': 45,
                    '1 min': 60,
                    '1.5 min': 90,
                    '2 min': 120,
                  }[v],
                ),
              ),
            ),
            const SizedBox(height: 18),
            PurpleButton(
              label: 'Done',
              onPressed: () => Navigator.pop(context, value),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _title(String text) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 7),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
  );
  String _difficulty(Difficulty d) =>
      ['Random', 'Easy', 'Medium', 'Hard'][d.index];
  String _durationChoice(int d) => const {
    30: '30 sec',
    45: '45 sec',
    60: '1 min',
    90: '1.5 min',
    120: '2 min',
  }[d]!;
}
