// lib/main.dart
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Import flutter_dotenv

// Import the new app root and logger
import 'src/app.dart';
import 'src/utils/logger.dart';

// Keep the global cameras list here for initialization
List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load the .env file
  try {
    await dotenv.load(fileName: ".env");
    logError('Env Load', '.env file loaded successfully.');
  } catch (e) {
    logError('Env Load Error', 'Could not load .env file: $e');
    // Handle error appropriately, maybe exit or use a default key
  }

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  try {
    cameras = await availableCameras();
    if (cameras.isEmpty) {
      logError('Camera Error', 'No cameras found on this device.');
      // Handle the case where no cameras are available
      // Maybe show an error message or exit the app
    } else {
      logError('Camera Info', '${cameras.length} cameras found.');
    }
  } on CameraException catch (e) {
    logError('Camera Error',
        'Failed to get available cameras: ${e.code} ${e.description}');
    // Handle camera initialization error
  } catch (e) {
    logError('Camera Error', 'An unexpected error occurred: $e');
    // Handle other potential errors
  }

  // Pass the initialized cameras list to the app widget
  runApp(CameraApp(cameras: cameras));
}
