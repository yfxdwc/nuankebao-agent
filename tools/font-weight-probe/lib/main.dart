// ============================================
// 字重真机探测 (font weight probe)
// ============================================
//
// 目的: 回答「Android 系统字体 (CJK 回退) 对 font-weight 400/500/600/700
//       是否真的渲染出不同笔画粗细」。
//
// 为什么必须真机: Flutter 用引擎侧字体匹配 (Skia + 平台 fontconfig)。
//   - 模拟器 = AOSP Noto Sans CJK
//   - 主人手机 = 厂商 ROM 字体 (MiSans / HarmonyOS Sans / OPPO Sans / 一加 ...)
//   两者可用字重集合不同 → 结论不能互相代替。
//
// 判据 (客观, 不靠肉眼):
//   1. 同一串文字, 不同字重离屏渲染 → RGBA 字节 hash
//      hash 相同 = 引擎选中的是**同一个字面** (该字重不存在)
//   2. 墨迹占比 (ink ratio) + 平均笔画游程 (mean run length)
//      越重 → 墨多 → 笔画粗
//   3. 与 w400 的"是否同一字面"对比 = 决定性判据
//
// 输出: logcat 里 `PROBEDATA:{json}` 一行一条
//   adb logcat -d | grep PROBEDATA

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

void main() => runApp(const ProbeApp());

// ---- 被测样本 ----

class Sample {
  const Sample(this.label, this.style);
  final String label;
  final TextStyle style;
}

const String kText = '王秀英 3天未联系 复购';
const String kTextShort = '客户跟进';
const String kTextHeavy = '养生记录 部位 状态 用料 效果';

const double kFontSize = 15; // = AppType.md (B 档正文)

List<Sample> buildSamples() => const [
      Sample('w300', TextStyle(fontSize: kFontSize, fontWeight: FontWeight.w300)),
      Sample('w400', TextStyle(fontSize: kFontSize, fontWeight: FontWeight.w400)),
      Sample('w500', TextStyle(fontSize: kFontSize, fontWeight: FontWeight.w500)),
      Sample('w600', TextStyle(fontSize: kFontSize, fontWeight: FontWeight.w600)),
      Sample('w700', TextStyle(fontSize: kFontSize, fontWeight: FontWeight.w700)),
      Sample('w900', TextStyle(fontSize: kFontSize, fontWeight: FontWeight.w900)),
      // 备选方案 A: 显式指名 Android 的 medium 家族别名
      Sample('sans-serif-medium@w500',
          TextStyle(fontSize: kFontSize, fontFamily: 'sans-serif-medium', fontWeight: FontWeight.w500)),
      Sample('sans-serif-medium@w600',
          TextStyle(fontSize: kFontSize, fontFamily: 'sans-serif-medium', fontWeight: FontWeight.w600)),
      // 备选方案 B: fontFamilyFallback 里塞 medium
      Sample('fallback[sfm]@w500', TextStyle(fontSize: kFontSize, fontWeight: FontWeight.w500, fontFamilyFallback: ['sans-serif-medium'])),
      // 备选方案 C: 打包字体族名 (若将来 bundle MiSans / HarmonyOS Sans)
      Sample('MiSans@w500', TextStyle(fontSize: kFontSize, fontFamily: 'MiSans', fontWeight: FontWeight.w500)),
      Sample('HarmonyOS@w500', TextStyle(fontSize: kFontSize, fontFamily: 'HarmonyOS Sans SC', fontWeight: FontWeight.w500)),
    ];

class ProbeApp extends StatelessWidget {
  const ProbeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '字重探测',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.light),
      home: const ProbePage(),
    );
  }
}

class ProbePage extends StatefulWidget {
  const ProbePage({super.key});

  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage> {
  String _status = '测量中…';
  List<_Result> _results = const [];
  Map<String, Object?> _verdict = const {};
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final out = <_Result>[];
    try {
      for (final s in buildSamples()) {
        final r = await _measure(s.label, kText, s.style);
        out.add(r);
        debugPrint('PROBEDATA:${jsonEncode(r.toJson())}');
      }

      // 换一串字复测 (防个别字形巧合)
      for (final t in [kTextShort, kTextHeavy]) {
        for (final w in [FontWeight.w400, FontWeight.w500, FontWeight.w600]) {
          final r = await _measure('${t.substring(0, 2)}@w${w.value}', t,
              TextStyle(fontSize: kFontSize, fontWeight: w));
          debugPrint('PROBEDATA:${jsonEncode(r.toJson())}');
        }
      }

      final v = _verdictOf(out);
      debugPrint('PROBEVERDICT:${jsonEncode(v)}');

      if (mounted) {
        setState(() {
          _results = out;
          _verdict = v;
          _done = true;
          _status = '完成';
        });
      }
    } catch (e, st) {
      debugPrint('PROBEERROR:$e\n$st');
      if (mounted) setState(() => _status = '出错: $e');
    }
  }

  /// 核心: 离屏渲染 → 像素统计
  Future<_Result> _measure(String label, String text, TextStyle style) async {
    const int bg = 0xFFFFFFFF;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style.copyWith(color: const Color(0xFF1A1A1A))),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();

    final w = tp.width.ceil() + 4;
    final h = tp.height.ceil() + 4;

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(bg),
    );
    tp.paint(canvas, const Offset(2, 2));
    final img = await rec.endRecording().toImage(w, h);
    final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = bd!.buffer.asUint8List();

    return _Result(
      label: label,
      text: text,
      width: w,
      height: h,
      hash: _fnv1a(bytes),
      inkRatio: _inkRatio(bytes, bg),
      meanRun: _meanRunLength(bytes, bg),
      advance: tp.width,
    );
  }

  /// 与 w400 比: 同字面 = 该字重不存在 (引擎回退)
  Map<String, Object?> _verdictOf(List<_Result> rs) {
    _Result? pick(String prefix) {
      for (final r in rs) {
        if (r.label == prefix) return r;
      }
      return null;
    }

    final w400 = pick('w400');
    final out = <String, Object?>{};
    for (final w in ['w300', 'w500', 'w600', 'w700', 'w900']) {
      final r = pick(w);
      if (r == null || w400 == null) continue;
      out[w] = {
        'sameAsW400': r.hash == w400.hash,
        'inkRatio': r.inkRatio,
        'deltaInkVs400': double.parse((r.inkRatio - w400.inkRatio).toStringAsFixed(4)),
        'distinctWidth': r.width != w400.width,
      };
    }
    final sfm = pick('sans-serif-medium@w500');
    if (sfm != null && w400 != null) {
      out['sans-serif-medium'] = {
        'sameAsW400': sfm.hash == w400.hash,
        'inkRatio': sfm.inkRatio,
        'deltaInkVs400': double.parse((sfm.inkRatio - w400.inkRatio).toStringAsFixed(4)),
      };
    }
    return out;
  }

  static int _fnv1a(Uint8List b) {
    var h = 0x811c9dc5;
    for (final x in b) {
      h ^= x;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  /// 墨迹占比: 非背景像素 / 总像素
  static double _inkRatio(Uint8List bytes, int bg) {
    final bgr = (bg >> 16) & 0xFF, bgg = (bg >> 8) & 0xFF, bgb = bg & 0xFF;
    var ink = 0;
    final n = bytes.length ~/ 4;
    for (var i = 0; i < n; i++) {
      final r = bytes[i * 4], g = bytes[i * 4 + 1], b = bytes[i * 4 + 2];
      if (r != bgr || g != bgg || b != bgb) ink++;
    }
    return double.parse((ink / n).toStringAsFixed(5));
  }

  /// 平均笔画游程: 连续"墨"像素的平均长度 ≈ 笔画粗细
  /// (整块当一维扫, 背景像素即断点 — 得到的是字形笔画横截的平均宽度)
  static double _meanRunLength(Uint8List bytes, int bg) {
    final bgr = (bg >> 16) & 0xFF, bgg = (bg >> 8) & 0xFF, bgb = bg & 0xFF;
    // 从外部无法拿宽, 用 sq 近似: 把整块当一维, 遇背景即断
    var run = 0, total = 0, count = 0;
    final n = bytes.length ~/ 4;
    for (var i = 0; i < n; i++) {
      final r = bytes[i * 4], g = bytes[i * 4 + 1], b = bytes[i * 4 + 2];
      final isInk = (r != bgr || g != bgg || b != bgb);
      if (isInk) {
        run++;
      } else if (run > 0) {
        total += run;
        count++;
        run = 0;
      }
    }
    return count == 0 ? 0 : total / count;
  }

  @override
  Widget build(BuildContext context) {
    final samples = buildSamples();
    return Scaffold(
      appBar: AppBar(title: Text('字重探测 · $_status')),
      body: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('① 肉眼对照 (同一串字, 只改字重)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final s in samples)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text(s.label, style: const TextStyle(fontSize: 12, color: Color(0xFF6B6B6B))),
                    ),
                    Expanded(child: Text(kText, style: s.style)),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            if (_done) ...[
              const Text('② 客观判据 (同 hash = 引擎选了同一个字面 = 该字重不存在)',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                color: const Color(0xFFF7F2EA),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in _verdict.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${e.key}  →  ${jsonEncode(e.value)}',
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('③ 各样本明细', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              for (final r in _results)
                Text(
                  '${r.label.padRight(22)} ink=${r.inkRatio.toStringAsFixed(4)}  run=${r.meanRun.toStringAsFixed(2)}  hash=${r.hash.toRadixString(16)}',
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
            ] else
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('测量中…')),
              ),
          ],
        ),
      ),
    );
  }
}

class _Result {
  _Result({
    required this.label,
    required this.text,
    required this.width,
    required this.height,
    required this.hash,
    required this.inkRatio,
    required this.meanRun,
    required this.advance,
  });

  final String label;
  final String text;
  final int width;
  final int height;
  final int hash;
  final double inkRatio;
  final double meanRun;
  final double advance;

  Map<String, Object?> toJson() => {
        'label': label,
        'text': text,
        'size': '${width}x$height',
        'hash': hash.toRadixString(16),
        'ink': inkRatio,
        'run': meanRun,
        'advance': double.parse(advance.toStringAsFixed(2)),
      };
}
