# UI 字重真机验证 (Android CJK) — B4 立项 (2026-09-24)

> **目的**: 验证 Android 系统字体 (CJK 回退) 对 `font-weight` 400/500/600/700 是否真渲染出不同笔画粗细。
>
> **状态**: **尚未在主人真机验证** (本批没设备接入 adb)
>
> **配套程序**: `tools/font-weight-probe/` (独立 Flutter 工程, 已落地, 可跑)

## 为什么要验

`docs/ui-principles.md` **原则 2「层级靠对比，不靠放大」** = 靠字重 + 颜色建立层级:

| 层级 | 字号 | 字重 | 颜色 |
|---|---|---|---|
| 页面标题 | 20 | 600 | 主文字 |
| 区块标题 | 17 | 600 | 主文字 |
| 条目主文 | 15 | 500 | 主文字 |
| 条目副文 | 13 | 400 | 次文字 |
| 辅助/角标 | 12 | 400 | 三级文字 |

**前提**: `w500` 跟 `w400` 真有笔画粗细区别 —— 中老年用户对「细」到「粗」敏感, w500 = 中等重,
w600 = 加粗, w400 = 常规, 三个档位真起作用, 层级才立得起来。

### 风险: Android CJK 回退字体的字重覆盖不全

Android 默认字体 = Roboto + Noto Sans CJK (系统语言是中文时, 汉字走 Noto)。
Noto Sans CJK 在不同 OEM ROM 上:

| ROM | 主字体 | medium (500) 支持 |
|---|---|---|
| AOSP (模拟器) | Noto Sans CJK | ✅ 全字重 |
| 华为 EMUI/HarmonyOS | HarmonyOS Sans SC | ✅ (主) |
| 小米 MIUI/HyperOS | MiSans VF | ✅ |
| OPPO ColorOS | OPPO Sans | ✅ |
| VIVO OriginOS | 思源黑体 | ✅ |

**理论上都支持** —— 但实际「理论」常常骗人: Android 8 之前的中文回退字体**只装 Regular**，
medium 走的是**字面合成** (Fake Bold, 笔画外面贴一圈) 而不是真笔画变粗。
Fake Bold 在中文字符上看起来糊, 跟「真 medium」完全不是一回事。

如果主人手机 (未知 OEM) 的中文字面不支持 medium:

- 原则 2 「字重建层级」**在中文上失效**
- 必须改方案 A: 「颜色 + 字号」建层级 (但中文范围已窄, 字号再分级很挤)
- 必须改方案 B: 打包 MiSans VF / HarmonyOS Sans SC 子集 (2-3 MB, 主人拍板)
- 必须改方案 C: 接受现状, 但**明文告知销售员这是字体问题不是 app bug**

**总之必须真机验, 不能拍脑袋**。

## 怎么验

### 准备工作

1. 拿主人手机 (待主人提供, 已知型号)
2. `adb connect <手机IP>:5555` (或 USB)
3. 装本工具: `adb install -r tools/font-weight-probe/build/app/outputs/flutter-apk/app-debug.apk`

### 跑探测

```bash
cd tools/font-weight-probe
flutter pub get
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb logcat -c
adb logcat | grep -E "PROBEDATA|PROBEVERDICT"
# 在手机上打开「字重探测」app → 自动跑 (1-2 秒)
# logcat 刷出 PROBEDATA 行 → 完成
```

### 输出怎么读

每行 `PROBEDATA:{json}`:
```json
{"label":"w400","text":"王秀英 3天未联系 复购","size":"330x24","hash":"a1b2c3d4","ink":0.182,"run":1.84,"advance":330.0}
{"label":"w500","text":"...","hash":"a1b2c3d4","ink":0.182,"run":1.84,...}
```

最后一行 `PROBEVERDICT:{json}` —— 对每个字重 vs w400 比:
```json
{"w500":{"sameAsW400":true,"inkRatio":0.182,"deltaInkVs400":0,"distinctWidth":false}, ...}
```

## 怎么写 (判据)

| 现象 | 结论 |
|---|---|
| `w500.sameAsW400 == true` | **系统中文字面无 medium** → 原则 2 在中文上失效 |
| `w500.sameAsW400 == false && w500.deltaInkVs400 > 0.005` | 真 medium 起作用 ✅ |
| `w600.sameAsW400 == true` | 加粗 (600) 也没真笔画 → 走的是 Fake Bold |
| `sans-serif-medium@w500.sameAsW400 == false` | `sans-serif-medium` 家族别名能拿到 medium |

### 两种后续方案 (验出「中文无 medium」时)

| 方案 | 代价 | 收益 |
|---|---|---|
| **A. 退回「颜色 + 字号」建层级** | 0 (改 `AppType.lg/md/sm` 字号差) | 适用所有手机, 0 部署成本 |
| **B. 打包 MiSans VF 子集** | 2-3 MB APK + 部署时只下中文字面 + 主题字号映射 | 全套 w500/w600 真起作用, 跟原则 2 设计一致 |
| **C. 不动, 明示限制** | 0 | 在 docs/ 写明现状, 等主人拍 |

**当前默认**: 等真机数据出来再拍 (B4 留作后续 ticket)。

## 当前状态 (B4, 2026-09-24 钉)

| 步骤 | 状态 |
|---|---|
| 探测程序代码已落地 | ✅ `tools/font-weight-probe/lib/main.dart` |
| 程序可编译成 APK | ✅ (未实跑过 build, 留待主人第一次跑验证) |
| 程序装到主人手机 | ❌ **未做** —— 手机未接入 adb |
| 跑探测 + 收 logcat | ❌ **未做** |
| 写入本文件结论 | ❌ **未做** |
| 主人拍「字体方案 A/B/C」 | ❌ **未做** |

**这条以后是 B5/B6 的事**。本批 B4 的贡献:

1. 把验证程序**搬进仓** (`tools/font-weight-probe/`), 不再依赖 `/tmp/fontprobe/`
2. 把跑法/判据**写进仓** (本文档), 三个月后回看不必重想
3. **诚实记录「未验证」**这个状态, 不假装验过了

## 工具历史

| 日期 | 变化 |
|---|---|
| 2026-09-23 | `/tmp/fontprobe/app/` 临时程序 (P3 配合 B0a 探索期) |
| 2026-09-24 | 搬入仓 `tools/font-weight-probe/` + README + 本验证文档 |