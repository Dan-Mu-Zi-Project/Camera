import 'package:flutter/material.dart';

class ShutterButton extends StatelessWidget {
  final bool isTakingPicture;
  final bool isShutterPressed;
  final VoidCallback? onTap;
  final VoidCallback? onTapDown;
  final VoidCallback? onTapUp;
  final VoidCallback? onTapCancel;
  final Widget? indicator;

  const ShutterButton({
    super.key,
    required this.isTakingPicture,
    required this.isShutterPressed,
    this.onTap,
    this.onTapDown,
    this.onTapUp,
    this.onTapCancel,
    this.indicator,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onTapDown: onTapDown != null ? (_) => onTapDown!() : null,
      onTapUp: onTapUp != null ? (_) => onTapUp!() : null,
      onTapCancel: onTapCancel,
      borderRadius: BorderRadius.circular(40),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 90,
            height: 90,
            child: indicator,
          ),
          AnimatedScale(
            scale: isShutterPressed ? 0.88 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeInOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isTakingPicture ? Colors.grey[300] : Colors.white,
                border: Border.all(
                  color: Colors.white.withOpacity(0.7),
                  width: 6,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: null,
            ),
          ),
        ],
      ),
    );
  }
}
