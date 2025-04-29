// lib/main.dart
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Import the new app root and logger
import 'src/app.dart';
import 'src/utils/logger.dart';

// Keep the global cameras list here for initialization
List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    // Use the logger from the utils file
    logError('Camera Error',
        'Error initializing cameras: ${e.code}\n${e.description}');
    cameras = [];
  }

  // Pass the initialized cameras list to the app widget
  runApp(CameraApp(cameras: cameras));
}

// Removed CameraApp, ErrorScreen, CameraScreen, _CameraScreenState, _logError
