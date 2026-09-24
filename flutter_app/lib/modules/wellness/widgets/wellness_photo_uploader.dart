// ============================================
// 养生照片上传 (Plan F2.5)
// 拍照 / 选图 → 缩略图 + 删除按钮 + 上传服务器
// 中老年大字 + 大触摸按钮
// ============================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/widgets/app_section.dart';

import '../../../core/theme/tokens.g.dart';
class WellnessPhotoUploader extends StatefulWidget {
  /// 已上传的 URL 列表（来自 model）
  final List<String> existingUrls;

  /// 照片变更回调（已上传 URL 列表）
  final ValueChanged<List<String>> onChanged;

  /// 成功上传一张照片后回调 (用量埋点: record_photo_taken)
  final VoidCallback? onPhotoUploaded;

  /// 最多几张 (2026-09-24 主人: 「上传照片最多 5 张, 照片等宽排在同一行」)
  final int maxPhotos;

  const WellnessPhotoUploader({
    super.key,
    required this.onChanged,
    this.onPhotoUploaded,
    this.existingUrls = const [],
    this.maxPhotos = 5,
  });

  @override
  State<WellnessPhotoUploader> createState() => _WellnessPhotoUploaderState();
}

class _WellnessPhotoUploaderState extends State<WellnessPhotoUploader> {
  late List<String> _urls;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _urls = List.from(widget.existingUrls);
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_urls.length >= widget.maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '最多 ${widget.maxPhotos} 张照片',
            style: const TextStyle(fontSize: AppTheme.fontMd),
          ),
        ),
      );
      return;
    }

    final picker = ImagePicker();
    try {
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1920,
      );
      if (picked == null) return;

      setState(() => _uploading = true);
      // 上传
      final bytes = await picked.readAsBytes();
      final base64Data = base64Encode(bytes);
      final url = await _uploadPhoto(base64Data);
      setState(() {
        _urls.add(url);
        _uploading = false;
      });
      widget.onChanged(_urls);
      widget.onPhotoUploaded?.call();
    } catch (e) {
      setState(() => _uploading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '上传失败: $e',
            style: const TextStyle(fontSize: AppTheme.fontMd),
          ),
        ),
      );
    }
  }

  Future<String> _uploadPhoto(String base64Data) async {
    // 通过 photoServiceProvider 注入的服务上传
    // 动态 import 避免循环依赖
    final container = WellnessPhotoUploaderScope.of(context);
    if (container == null) {
      throw Exception('PhotoService not provided');
    }
    return await container(base64Data);
  }

  void _removePhoto(int index) {
    setState(() => _urls.removeAt(index));
    widget.onChanged(_urls);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行 (2026-09-24 主人: 「拍照和相册这两个按键也可以收到与标题
        //   「部位照片」同一行」) —— 右侧两个紧凑按钮, 不再各占半行 64pt 大按钮
        AppSectionHeader(
          title: '部位照片',
          subtitle: '已上传 ${_urls.length} / ${widget.maxPhotos}',
          padding: EdgeInsets.zero,
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: _uploading ? null : () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt, size: AppSize.iconSm),
                label: const Text('拍照', style: TextStyle(fontSize: AppTheme.fontSm)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppSize.controlLg),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: AppSpace.s8),
              OutlinedButton.icon(
                onPressed: _uploading ? null : () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library, size: AppSize.iconSm),
                label: const Text('相册', style: TextStyle(fontSize: AppTheme.fontSm)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppSize.controlLg),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.s12),

        // 照片条: **固定 maxPhotos 个等宽槽位, 永远一行** (2026-09-24 主人:
        //   「照片等宽排在同一行」)。
        //   为什么固定槽位数 (而不是按已有张数均分): 张数变化时缩略图不会忽大忽小,
        //   空槽位也顺带表达了"还能加几张" (原则 1 密度 + 稳定布局)。
        Row(
          key: const ValueKey('photoStrip'),
          children: [
            for (var i = 0; i < widget.maxPhotos; i++) ...[
              if (i > 0) const SizedBox(width: AppSpace.s6),
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: i < _urls.length
                      ? _photoTile(_urls[i], () => _removePhoto(i))
                      : Container(
                          // 空槽位: 浅底提示位 (不可点, 拍照/相册按钮在标题行)
                          key: ValueKey('photoSlot-empty-$i'),
                          decoration: BoxDecoration(
                            color: context.tokens.surfaceSubtle,
                            borderRadius: BorderRadius.circular(AppRadius.r12),
                          ),
                        ),
                ),
              ),
            ],
          ],
        ),
        if (_uploading) ...[
          const SizedBox(height: AppSpace.s12),
          const Row(
            children: [
              SizedBox(
                width: AppSpace.s20,
                height: AppSpace.s20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: AppSpace.s8),
              Text('上传中...', style: TextStyle(fontSize: AppTheme.fontSm)),
            ],
          ),
        ],
      ],
    );
  }

  /// 照片缩略图 —— **填满父槽位** (等宽由外层 Expanded 决定, 不写固定尺寸)
  Widget _photoTile(String url, VoidCallback onRemove) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.r12),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: AppTheme.bgWarm,
              child: const Icon(Icons.broken_image, color: AppTheme.textSecondary),
            ),
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return Container(
                color: AppTheme.bgWarm,
                child: const Center(
                  child: SizedBox(
                    width: AppSpace.s24,
                    height: AppSpace.s24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            },
          ),
        ),
        Positioned(
          top: AppSpace.s2,
          right: AppSpace.s2,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(AppSpace.s2),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: AppSize.iconSm),
            ),
          ),
        ),
      ],
    );
  }
}

/// Provider 注入: 让 widget 可拿到 PhotoService
class WellnessPhotoUploaderScope extends InheritedWidget {
  final Future<String> Function(String base64) upload;

  const WellnessPhotoUploaderScope({
    super.key,
    required this.upload,
    required super.child,
  });

  static Future<String> Function(String)? of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<WellnessPhotoUploaderScope>();
    return scope?.upload;
  }

  @override
  bool updateShouldNotify(WellnessPhotoUploaderScope oldWidget) =>
      upload != oldWidget.upload;
}