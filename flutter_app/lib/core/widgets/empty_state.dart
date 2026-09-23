// 空状态 / 加载失败 (中老年大白话)
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

import '../theme/tokens.g.dart';
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;
  final VoidCallback? onAction;
  final String? actionLabel;

  const EmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.hint,
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppSize.avatarLg, color: AppTheme.textSecondary),
            const SizedBox(height: AppSpace.s16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: AppTheme.fontMd,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: AppSpace.s8),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: AppTheme.fontSm,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: AppSpace.s16),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(160, AppSize.buttonLgHeight),
                ),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(fontSize: AppTheme.fontMd),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 加载中 (大圆圈)
/// 加载中 -- size: sm/md/lg, 默认 md (= 主按钮大小, 48)
///   sm = 16 (按钮内 / 列表右侧 inline)
///   md = 48 (页面级 / 卡片级, 默认)
///   lg = 64 (空态 hero 区)
///
/// ⚠ 按钮内 (高度 20-26) 不要用 LoadingState -- 它的 Center 包装会破坏按钮布局。
///   那种场景直接用 SizedBox + spinner (示例尺寸 20 仅供参考, 真用查 AppSize 令牌)。
class LoadingState extends StatelessWidget {
  final double? size;
  final double? strokeWidth;
  final Color? color;
  const LoadingState({super.key, this.size, this.strokeWidth, this.color});

  @override
  Widget build(BuildContext context) {
    final s = size ?? AppSize.buttonLgHeight;       // md 默认 48
    return Center(
      child: SizedBox(
        width: s,
        height: s,
        child: CircularProgressIndicator(
          strokeWidth: strokeWidth ?? 3,
          color: color,
        ),
      ),
    );
  }
}

/// 加载失败 (大白话)
class ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  const ErrorState({super.key, required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off,
      title: '网络不太好',
      hint: '请检查网络后重试一下',
      onAction: onRetry,
      actionLabel: '重试',
    );
  }
}