// 大 FAB (中老年妇女版, 80pt 圆形)
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class BigFab extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String? tooltip;
  final Color? backgroundColor;

  const BigFab({
    super.key,
    required this.onPressed,
    this.icon = Icons.add,
    this.tooltip,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppTheme.fabSize,
      height: AppTheme.fabSize,
      child: FloatingActionButton(
        onPressed: onPressed,
        tooltip: tooltip,
        backgroundColor: backgroundColor ?? AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 6,
        child: Icon(icon, size: 36),
      ),
    );
  }
}