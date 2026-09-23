// 大按钮 (中老年妇女版, 64pt 高)
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

import '../theme/tokens.g.dart';
class BigButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool loading;

  const BigButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? AppTheme.primary;
    final fg = foregroundColor ?? Colors.white;
    return SizedBox(
      width: double.infinity,
      height: AppTheme.buttonLgHeight,
      child: ElevatedButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? SizedBox(
                width: AppSpace.s24,
                height: AppSpace.s24,
                child: CircularProgressIndicator(
                  color: fg,
                  strokeWidth: 3,
                ),
              )
            : (icon != null ? Icon(icon, size: AppSize.iconXl) : const SizedBox.shrink()),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: AppTheme.fontMd,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: bg.withOpacity(0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.r12),
          ),
        ),
      ),
    );
  }
}