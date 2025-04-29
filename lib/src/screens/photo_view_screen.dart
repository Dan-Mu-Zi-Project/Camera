// lib/src/screens/photo_view_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';

class PhotoViewScreen extends StatelessWidget {
  final String imagePath;

  const PhotoViewScreen({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        // Optional: Add actions like delete or share
      ),
      body: Center(
        child: InteractiveViewer(
          // Allows panning and zooming
          panEnabled: true,
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.file(
            File(imagePath),
            fit: BoxFit.contain, // Ensure the whole image is visible
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Text(
                  'Could not load image.',
                  style: TextStyle(color: Colors.white),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
