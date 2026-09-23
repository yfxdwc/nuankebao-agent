import 'dart:convert' show base64, base64Url;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:nuankebao/core/theme/tokens.g.dart';
/// 照片选择组件 (相机/相册)
class PhotoPicker extends StatefulWidget {
  final List<String> photoUrls;
  final void Function(List<String>) onChanged;
  final int maxPhotos;

  const PhotoPicker({
    super.key,
    required this.photoUrls,
    required this.onChanged,
    this.maxPhotos = 9,
  });

  @override
  State<PhotoPicker> createState() => _PhotoPickerState();
}

class _PhotoPickerState extends State<PhotoPicker> {
  final _picker = ImagePicker();
  bool _loading = false;

  Future<void> _pickImage(ImageSource source) async {
    if (widget.photoUrls.length >= widget.maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('最多 ${widget.maxPhotos} 张照片')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 80,
      );
      if (file == null) return;

      // 读取为 bytes → base64
      final bytes = await File(file.path).readAsBytes();
      final base64 = 'data:image/jpeg;base64,${_bytesToBase64(bytes)}';

      // 调用外部 onChanged (由父组件上传 + 更新 URL)
      widget.onChanged([...widget.photoUrls, base64]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择照片失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _bytesToBase64(List<int> bytes) {
    return base64.encode(bytes);
  }

  void _showPicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('照片', style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: AppSpace.s8),
        SizedBox(
          height: AppSpace.s100,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // 已有照片
              ...widget.photoUrls.asMap().entries.map((e) {
                final isBase64 = e.value.startsWith('data:');
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpace.s8),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.r8),
                        child: isBase64
                            ? Image.memory(
                                _decodeBase64(e.value),
                                width: AppSpace.s100,
                                height: AppSpace.s100,
                                fit: BoxFit.cover,
                              )
                            : Image.network(
                                e.value.startsWith('http')
                                    ? e.value
                                    : 'http://192.168.1.200:3003${e.value}',
                                width: AppSpace.s100,
                                height: AppSpace.s100,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: AppSpace.s100,
                                  height: AppSpace.s100,
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.broken_image),
                                ),
                              ),
                      ),
                      Positioned(
                        top: AppSpace.s2,
                        right: AppSpace.s2,
                        child: GestureDetector(
                          onTap: () {
                            final newList = List<String>.from(widget.photoUrls);
                            newList.removeAt(e.key);
                            widget.onChanged(newList);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(AppSpace.s2),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: AppSpace.s16),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              // 添加按钮
              if (widget.photoUrls.length < widget.maxPhotos)
                GestureDetector(
                  onTap: _loading ? null : _showPicker,
                  child: Container(
                    width: AppSpace.s100,
                    height: AppSpace.s100,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[400]!, style: BorderStyle.solid, width: 1),
                      borderRadius: BorderRadius.circular(AppRadius.r8),
                    ),
                    child: _loading
                        ? const Center(
                            child: SizedBox(
                              width: AppSpace.s20,
                              height: AppSpace.s20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : const Icon(Icons.add_a_photo,
                            color: Colors.grey, size: AppSpace.s32),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Uint8List _decodeBase64(String dataUrl) {
    final base64 = dataUrl.split(',').last;
    return Uint8List.fromList(base64Url.decode(base64));
  }
}

// (imports at top)
