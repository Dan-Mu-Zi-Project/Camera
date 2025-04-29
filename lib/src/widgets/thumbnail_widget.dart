import 'dart:io';
import 'package:flutter/material.dart';

class ThumbnailWidget extends StatelessWidget {
  final String? imagePath;
  final VoidCallback? onTap;

  const ThumbnailWidget({
    super.key,
    required this.imagePath,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 1),
          borderRadius: BorderRadius.circular(12),
          color: Colors.black26,
        ),
        child: imagePath != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  File(imagePath!),
                  fit: BoxFit.cover,
                  width: 54,
                  height: 54,
                ),
              )
            : const Icon(Icons.photo, color: Colors.white54, size: 32),
      ),
    );
  }
}
