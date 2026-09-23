// ============================================
// 养生照片上传 (Plan F2.5)
// 拍照 / 选图 → 缩略图 + 删除按钮 + 上传服务器
// 中老年大字 + 大触摸按钮
// ============================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';

import '../../../core/theme/tokens.g.dart';
class WellnessPhotoUploader extends StatefulWidget {
  /// 已上传的 URL 列表（来自 model）
  final List<String> existingUrls;

  /// 照片变更回调（已上传 URL 列表）
  final ValueChanged<List<String>> onChanged;

  /// 成功上传一张照片后回调 (用量埋点: record_photo_taken)
  final VoidCallback? onPhotoUploaded;

  final int maxPhotos;

  const WellnessPhotoUploader({
    super.key,
    required this.onChanged,
    this.onPhotoUploaded,
    this.existingUrls = const [],
    this.maxPhotos = 6,
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
        const Text(
          '部位照片',
          style: TextStyle(
            fontSize: AppTheme.fontMd,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpace.s4),
        Text(
          '已上传 ${_urls.length} / ${widget.maxPhotos}',
          style: const TextStyle(
            fontSize: AppTheme.fontSm,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpace.s12),

        // 已上传照片网格
        if (_urls.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _urls.asMap().entries.map((e) {
              final i = e.key;
              final url = e.value;
              return _photoTile(url, () => _removePhoto(i));
            }).toList(),
          ),

        const SizedBox(height: AppSpace.s12),

        // 上传按钮 (大按钮组)
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _uploading ? null : () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt, size: 28),
                label: const Text('拍照', style: TextStyle(fontSize: AppTheme.fontMd)),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 64)),
              ),
            ),
            const SizedBox(width: AppSpace.s12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _uploading ? null : () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library, size: 28),
                label: const Text('相册', style: TextStyle(fontSize: AppTheme.fontMd)),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 64)),
              ),
            ),
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

  Widget _photoTile(String url, VoidCallback onRemove) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.r12),
          child: Image.network(
            url,
            width: AppSpace.s96,
            height: AppSpace.s96,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: AppSpace.s96,
              height: AppSpace.s96,
              color: AppTheme.bgWarm,
              child: const Icon(Icons.broken_image, color: AppTheme.textSecondary),
            ),
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return Container(
                width: AppSpace.s96,
                height: AppSpace.s96,
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
          top: AppSpace.s4,
          right: AppSpace.s4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(AppSpace.s4),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 18),
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