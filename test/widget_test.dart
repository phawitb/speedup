import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speak_up/app_controller.dart';
import 'package:speak_up/camera_service.dart';
import 'package:speak_up/main.dart';
import 'package:speak_up/models.dart';
import 'package:speak_up/screens/recording_screen.dart';
import 'package:speak_up/screens/results_screen.dart';
import 'package:speak_up/screens/history_screen.dart';
import 'package:speak_up/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('record screen renders primary flow controls', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = await AppController.load();
    await tester.pumpWidget(
      SpeakUpApp(
        controller: controller,
        cameraService: CameraService.disabled(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('START'), findsOneWidget);
    expect(find.text('Day 1 🔥'), findsOneWidget);
    expect(find.textContaining('If you could live'), findsOneWidget);
    expect(find.text('Customize'), findsOneWidget);
    expect(find.byIcon(Icons.casino_outlined), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
  });

  testWidgets('random button cycles through topics before choosing one', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = await AppController.load();
    final original = controller.session.topic;
    var topicChanges = 0;
    var previous = original;
    controller.addListener(() {
      if (controller.session.topic != previous) {
        previous = controller.session.topic;
        topicChanges++;
      }
    });
    await tester.pumpWidget(
      SpeakUpApp(
        controller: controller,
        cameraService: CameraService.disabled(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.casino_outlined));
    await tester.pumpAndSettle();
    expect(controller.session.topic, isNot(original));
    expect(topicChanges, greaterThanOrEqualTo(5));
  });

  testWidgets('preview switches between Camera and Avatar modes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = await AppController.load();
    final camera = CameraService.disabled();
    await tester.pumpWidget(
      SpeakUpApp(controller: controller, cameraService: camera),
    );
    await tester.pumpAndSettle();
    expect(find.text('Camera'), findsOneWidget);
    await tester.tap(find.text('Camera'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Avatar'), findsOneWidget);
    expect(find.text('No camera or webcam found'), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(camera.faceTracking.state.faceDetected, isTrue);
  });

  testWidgets('settings sheet persists selected duration', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    final controller = await AppController.load();
    await tester.pumpWidget(
      SpeakUpApp(
        controller: controller,
        cameraService: CameraService.disabled(),
      ),
    );
    await tester.tap(find.byIcon(Icons.timer_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('00:30'));
    await tester.pumpAndSettle();

    expect(controller.settings.durationSeconds, 30);
    expect(find.text('00:30'), findsOneWidget);
  });

  test('settings copyWith preserves untouched values', () {
    const settings = PracticeSettings(
      durationSeconds: 60,
      topicCategory: 'General',
    );
    final changed = settings.copyWith(durationSeconds: 90);
    expect(changed.durationSeconds, 90);
    expect(changed.topicCategory, 'General');
  });

  testWidgets(
    'recording waits for capture and completion sheet fits the screen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({'duration': 30});
      final controller = await AppController.load();
      final camera = CameraService.disabled();
      addTearDown(camera.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildSpeakUpTheme(),
          home: RecordingScreen(controller: controller, cameraService: camera),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      // A missing platform recorder must not consume speaking time while the
      // system capture permission/setup is still pending.
      expect(find.text('00:30'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      await tester.tap(find.byIcon(Icons.lightbulb_outline_rounded));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Speaking Guide'), findsOneWidget);
      expect(find.text('Useful language'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pump(const Duration(milliseconds: 400));
      // Stop is disabled until camera capture is genuinely active. A failed
      // start must be visible and retryable instead of leaving a frozen timer.
      expect(find.text('Well done!'), findsNothing);
      expect(find.text('Retry Camera'), findsOneWidget);
      expect(find.text('00:30'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await camera.pause();
    },
  );

  testWidgets('history entries open their past analysis', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    final controller = await AppController.load();
    controller.setElapsed(30);
    await controller.completePractice();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildSpeakUpTheme(),
        home: HistoryScreen(
          controller: controller,
          cameraService: CameraService.disabled(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Practice History'), findsOneWidget);
    expect(find.text('Day Streak'), findsOneWidget);
    expect(find.text('Day 1'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Past Analysis'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    await tester.tap(find.text('Transcript'));
    await tester.pumpAndSettle();
    expect(find.text('Suggested correction'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'results combine scores and expose transcript corrections and revised version',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({});
      final controller = await AppController.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildSpeakUpTheme(),
          home: ResultsScreen(
            controller: controller,
            cameraService: CameraService.disabled(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Detailed Scores'), findsOneWidget);
      expect(find.text('Focus Next Time'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Transcript'));
      await tester.pumpAndSettle();
      expect(find.text('Suggested correction'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Revised'));
      await tester.pumpAndSettle();
      expect(find.text('A Smoother Version'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
