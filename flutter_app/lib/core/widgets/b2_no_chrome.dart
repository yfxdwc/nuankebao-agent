// ============================================
// B2 收口专用: 无壳容器 (Cards 渐退, B 档原则 4)
// ============================================
//
// B0a 没有专门的「无壳容器」组件, 因为它的使用频率不该有 (列表用 AppListRow, 区块
//   用 AppSection); 但 B2 把页面里几乎所有 Card( 都降到这里过渡。
//
// 视觉: 浅底圆角 (默认 tokens.surfaceCard), 不画边框, 不画阴影,
//   圆角同 AppRadius.card, 高度自适应子内容. 这就是 Card 拿掉 elevation/border 后的样子.
//
// 由于 Card 的命名参数太多 (margin, shape, clipBehavior, borderOnForeground, semanticContainer…),
//   本组件只暴露 child + 可选 margin + 可选 color —— 其他命名参数一律不要. B2 阶段
//   后续如果发现某页面需要 Card 的某个属性, 优先在该页面换成 Container 真正定制, 不要扩这里.
//
import 'package:flutter/material.dart';

import '../theme/theme_ext.dart';
import '../theme/tokens.g.dart';

/// 「B 档无壳容器」—— BoxDecoration 圆角 + 浅底 (无 border, 无 shadow).
///   Card 的去壳替身. 圆角 AppRadius.card, 颜色默认 context.tokens.surfaceCard.
class B2NoChrome extends StatelessWidget {
  final Widget child;

  /// 对 Card 的兼容: 老代码常 `margin: EdgeInsets.zero`, 这里直接透传 (无意义但保留).
  final EdgeInsetsGeometry? margin;

  /// 默认 context.tokens.surfaceCard; 显式给 `dangerSurface` / `surfaceSubtle` 等都行.
  final Color? color;

  const B2NoChrome({
    super.key,
    required this.child,
    this.margin,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final Widget inner = Container(
      decoration: BoxDecoration(
        color: color ?? context.tokens.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: child,
    );
    if (margin == null) return inner;
    return Padding(padding: margin!, child: inner);
  }
}
