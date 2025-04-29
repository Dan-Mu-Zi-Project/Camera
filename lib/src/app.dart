// lib/src/app.dart
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'screens/camera_screen.dart';
import 'screens/error_screen.dart';

class CameraApp extends StatelessWidget {
  final List<CameraDescription> cameras; // Receive cameras list
  const CameraApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Camera App',
      theme: ThemeData.dark(),
      home: cameras.isEmpty
          ? const ErrorScreen(
              message: 'No cameras available or permission denied.')
          : CameraScreen(cameras: cameras), // Pass cameras to CameraScreen
    );
  }
}
