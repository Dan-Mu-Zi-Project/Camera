// lib/src/screens/gallery_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'photo_view_screen.dart'; // Import the new screen

class GalleryScreen extends StatelessWidget {
  final List<String> imagePaths;

  const GalleryScreen({super.key, required this.imagePaths});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Photos'),
        backgroundColor: Colors.black,
      ),
      backgroundColor: Colors.black,
      body: imagePaths.isEmpty
          ? const Center(
              child: Text(
                'No photos saved yet.',
                style: TextStyle(color: Colors.white),
              ),
            )
          : GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, // Display 3 images per row
                crossAxisSpacing: 4.0,
                mainAxisSpacing: 4.0,
              ),
              itemCount: imagePaths.length,
              itemBuilder: (context, index) {
                // Display images in reverse order (newest first)
                final imagePath = imagePaths[imagePaths.length - 1 - index];
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PhotoViewScreen(imagePath: imagePath),
                      ),
                    );
                  },
                  child: Image.file(
                    File(imagePath),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      // Handle potential file reading errors
                      return Container(
                        color: Colors.grey[800],
                        child: const Icon(Icons.error_outline,
                            color: Colors.white),
                      );
                    },
                  ),
                );
              },
              padding: const EdgeInsets.all(4.0),
            ),
    );
  }
}
