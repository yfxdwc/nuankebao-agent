# font-weight-probe — Android 中文字重真机验证 (B4, 2026-09-24 落地)

> **目的**: 验证 Android 系统字体 (CJK 回退) 对 `font-weight` 400/500/600/700 是否真渲染出不同笔画粗细。
>
> **重要性**: 见 [`docs/ui-font-weight-verification.md`](../../docs/ui-font-weight-verification.md)。
> `docs/ui-principles.md` 原则 2「层级靠对比，不靠放大」= 靠字重 + 颜色建立层级，
> **前提是字重真的被字体区分**。如果 Android CJK 回退字体无 medium 笔画，原则 2 在真机上失效。

## 跑法

```bash
cd tools/font-weight-probe
flutter pub get
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb logcat -c   # 清旧日志
adb logcat | grep -E "PROBEDATA|PROBEVERDICT"
# 点 app 里的大按钮 (无按钮, 进 app 自动跑) → 1-2 秒完成 → logcat 出来
```

## 输出格式 (logcat)

每行 `PROBEDATA:{json}` —— 同一字串、同一字号、不同字重的渲染统计：
```json
{"label":"w400","text":"王秀英 3天未联系 复购","size":"330x24","hash":"a1b2c3d4","ink":0.182,"run":1.84,"advance":330.0}
{"label":"w500","text":"王秀英 3天未联系 复购","size":"330x24","hash":"a1b2c3d4","ink":0.182,"run":1.84,"advance":330.0}
{"label":"w600",...}
```

+ 一行 `PROBEVERDICT:{json}` —— 与 w400 比同字面 (= 该字重不存在) 总结。

## 判据

| 现象 | 结论 |
|---|---|
| `w500.hash == w400.hash` | 系统中文字面无 medium → 原则 2 在真机上失效 → 改用「颜色 + 字号」建层级, 或打包 MiSans / HarmonyOS Sans SC |
| `sans-serif-medium@w500.hash != w400.hash` | medium 家族别名可用 (但其他 weight 仍可能缺) |
| `w500.inkRatio > w400.inkRatio +0.005` | 墨量更厚, 中等字重真起作用 |

## 当前状态 (B4, 2026-09-24 钉)

- ✅ **本程序已落地, 可跑** (代码已在 `lib/main.dart`)
- ❌ **真机未验证**: 主人手机未接入 adb (AGENTS §5/§10 已知)
- 下一动作: 主人拿数据 → 跑本程序 → 看 logcat → 主人拍板

## 注意事项

- **不进 `flutter_app/` 主工程**: 这是独立的小工程, 避免污染 `pubspec.yaml` 体积
- **不进 git history 主分支监控**: 本目录是新加的, 无 preview framework 冻结关联
- 改 `pubspec.yaml` 不会影响主仓 `flutter_app/pubspec.yaml` (独立工程)