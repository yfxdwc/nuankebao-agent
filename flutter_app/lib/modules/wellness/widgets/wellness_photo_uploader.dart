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

  /// 还能再加吗 (满了给提示)
  bool _canAddMore() {
    if (_urls.length >= widget.maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '最多 ${widget.maxPhotos} 张照片',
            style: const TextStyle(fontSize: AppTheme.fontMd),
          ),
        ),
      );
      return false;
    }
    return true;
  }

  /// 拍照 (单张)
  Future<void> _pickFromCamera() async {
    if (!_canAddMore()) return;
    final picker = ImagePicker();
    try {
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1920,
      );
      if (picked == null) return;
      await _uploadAll([picked]);
    } catch (e) {
      _toast('上传失败: $e');
    }
  }

  /// 相册 (2026-09-24: 支持**多选**, 一次最多补到 5 张)
  Future<void> _pickFromGallery() async {
    if (!_canAddMore()) return;
    final picker = ImagePicker();
    try {
      final picked =
          await picker.pickMultiImage(imageQuality: 80, maxWidth: 1920);
      if (picked.isEmpty) return;
      await _uploadAll(picked);
    } catch (e) {
      _toast('上传失败: $e');
    }
  }

  /// 点空槽位 → 让用户选 拍照 / 相册 (2026-09-24: 空槽不再只是占位)
  Future<void> _chooseSource() async {
    if (!_canAddMore()) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('拍照', style: TextStyle(fontSize: AppTheme.fontMd)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选 (可多选)',
                  style: TextStyle(fontSize: AppTheme.fontMd)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    if (source == ImageSource.camera) {
      await _pickFromCamera();
    } else {
      await _pickFromGallery();
    }
  }

  /// 逐张上传 (超过上限的张数直接丢弃并告知)
  Future<void> _uploadAll(List<XFile> files) async {
    final remaining = widget.maxPhotos - _urls.length;
    final batch = files.take(remaining).toList();
    if (batch.isEmpty) return;
    setState(() => _uploading = true);
    var failed = 0;
    for (final f in batch) {
      try {
        final url = await _uploadPhoto(base64Encode(await f.readAsBytes()));
        if (!mounted) return;
        setState(() => _urls.add(url));
        widget.onPhotoUploaded?.call();
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() => _uploading = false);
    widget.onChanged(_urls);
    if (files.length > batch.length) {
      _toast('最多 ${widget.maxPhotos} 张, 多出的 ${files.length - batch.length} 张没上传');
    }
    if (failed > 0) _toast('$failed 张上传失败, 可再试一次');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: AppTheme.fontMd)),
      ),
    );
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
        // 标题行 (2026-09-24 主人二次拍板): 「既然已经可以直接点缩略图位置选择
        //   拍照/相册上传, 区块右上角的拍照和相册按键可以删除了。已上传数量移动到
        //   标题右侧」
        // 历史: 上一版把「拍照/相册」两个大按钮收到这一行; 现在连它们也删了 ——
        //   区块右上角的拍照和相册按键可以删除了。已上传数量移动到标题右侧」
        //   ⇒ 标题行只剩「部位照片 + 已上传 N / max」; 加照片统一走**点槽位**
        //     (空槽位上有相机图标, 点了弹"拍照 / 从相册选")。
        AppSectionHeader(
          title: '部位照片',
          padding: EdgeInsets.zero,
          action: Text(
            '已上传 ${_urls.length} / ${widget.maxPhotos}',
            style: TextStyle(
              fontSize: AppTheme.fontSm,
              color: context.tokens.textSecondary,
            ),
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
                      : InkWell(
                          // 空槽位 (2026-09-24): 点它直接加照片 (拍照/相册二选一),
                          //   不再只是占位
                          key: ValueKey('photoSlot-empty-$i'),
                          onTap: _uploading ? null : _chooseSource,
                          borderRadius: BorderRadius.circular(AppRadius.r12),
                          child: Container(
                            decoration: BoxDecoration(
                              color: context.tokens.surfaceSubtle,
                              borderRadius: BorderRadius.circular(AppRadius.r12),
                            ),
                            child: Icon(
                              Icons.add_a_photo_outlined,
                              size: AppSize.iconLg,
                              color: context.tokens.textTertiary,
                            ),
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