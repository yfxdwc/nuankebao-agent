// ============================================
// 子对话框 / 共享小组件 —— 客户域弹层 (年份 / 数字 / 标签输入 + 分组头数据载体)
//
// 本文件从 customers_page.dart 拆出 (2026-09-24, B1 客户域换装)
// 拆分原则: 跨页 (列表 / 详情 / 表单) 共用的小部件集中一处, 不重复实现.
// ============================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.g.dart';

// ============================================
// 年份选择 (出生年份) — 大白话: 滚到 1965 附近, 点 OK
// ============================================

class YearPickerDialog extends StatefulWidget {
  final int? initial;
  const YearPickerDialog({super.key, this.initial});

  @override
  State<YearPickerDialog> createState() => _YearPickerDialogState();
}

class _YearPickerDialogState extends State<YearPickerDialog> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.initial ?? 1980;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择出生年份'),
      content: SizedBox(
        height: 200,
        child: ListView.builder(
          itemCount: 100,
          itemBuilder: (context, i) {
            final y = 1940 + i;
            return ListTile(
              title: Text('$y年',
                  style: const TextStyle(fontSize: AppTheme.fontMd)),
              selected: y == _year,
              onTap: () {
                setState(() => _year = y);
                Navigator.of(context).pop(y);
              },
            );
          },
        ),
      ),
    );
  }
}

/// 月 / 日 数字选择器 (含「不清楚」= 返回 null 清空)
class NumberPickerDialog extends StatelessWidget {
  final String title;
  final int max;
  final int? initial;
  final String suffix;

  const NumberPickerDialog({
    super.key,
    required this.title,
    required this.max,
    required this.suffix,
    this.initial,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: AppTheme.fontLg)),
      contentPadding: const EdgeInsets.symmetric(vertical: AppSpace.s8),
      content: SizedBox(
        height: 300,
        width: 240,
        child: ListView.builder(
          itemCount: max + 1, // 第 0 项 = 不清楚
          itemBuilder: (context, i) {
            if (i == 0) {
              return ListTile(
                title: const Text('不清楚 / 清空',
                    style: TextStyle(fontSize: AppTheme.fontMd)),
                selected: initial == null,
                onTap: () => Navigator.of(context).pop(null),
              );
            }
            return ListTile(
              title: Text('$i$suffix',
                  style: const TextStyle(fontSize: AppTheme.fontMd)),
              selected: i == initial,
              onTap: () => Navigator.of(context).pop(i),
            );
          },
        ),
      ),
    );
  }
}

/// 标签输入 (健康标签新增弹层, 兼容老调用; 当前表单已用 inline 字段)
class TagInputDialog extends StatefulWidget {
  const TagInputDialog({super.key});

  @override
  State<TagInputDialog> createState() => _TagInputDialogState();
}

class _TagInputDialogState extends State<TagInputDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加健康标签'),
      content: TextField(
        controller: _controller,
        style: const TextStyle(fontSize: AppTheme.fontMd),
        autofocus: true,
        decoration: const InputDecoration(hintText: '如: 肩颈 / 睡眠差 / 体寒'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
        ElevatedButton(
          onPressed: () {
            final v = _controller.text.trim();
            if (v.isNotEmpty) Navigator.of(context).pop(v);
          },
          child: const Text('添加', style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
      ],
    );
  }
}

/// 分组表头数据 (列表渲染用的小载体)
class GroupHeaderData {
  final String level;
  final String label;
  final int count;
  const GroupHeaderData({
    required this.level,
    required this.label,
    required this.count,
  });
}