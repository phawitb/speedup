import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_controller.dart';
import 'camera_service.dart';
import 'screens/record_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final controller = await AppController.load();
  List<CameraDescription> cameras = const [];
  try {
    cameras = await availableCameras();
  } catch (_) {}
  final cameraService = CameraService(cameras);
  runApp(SpeakUpApp(controller: controller, cameraService: cameraService));
  cameraService.initialize();
}

class SpeakUpApp extends StatefulWidget {
  const SpeakUpApp({
    super.key,
    required this.controller,
    required this.cameraService,
  });
  final AppController controller;
  final CameraService cameraService;

  @override
  State<SpeakUpApp> createState() => _SpeakUpAppState();
}

class _SpeakUpAppState extends State<SpeakUpApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) widget.cameraService.pause();
    if (state == AppLifecycleState.resumed) widget.cameraService.resume();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SpeakUp!',
    debugShowCheckedModeBanner: false,
    theme: buildSpeakUpTheme(),
    home: RecordScreen(
      controller: widget.controller,
      cameraService: widget.cameraService,
    ),
  );
}
