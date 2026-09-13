# 主人手机无线调试配对 SOP

> **适用**: 暖客宝 Flutter 开发 (Web + Phone 并行)
> **前置**: 手机和服务器同 WiFi (192.168.1.x 网段)
> **ADR**: `adr/0003-flutter-dev-workflow.md` §5

---

## 一次性配对 (5 分钟)

### 步骤 1: 手机开开发者选项 + 无线调试

```
设置 → 关于手机 → 连点 "版本号" 7 次 → 提示 "已开启开发者模式"
返回 → 系统和更新 → 开发者选项 →
  ✅ USB 调试 (勾上, 但不需要插 USB)
  ✅ 无线调试 (Android 11+ 才有, 进去)
```

### 步骤 2: 拿到 IP:PORT + 配对码

```
开发者选项 → 无线调试 → 点 "使用配对码配对设备"
  → 屏幕显示:
       IP 地址: 192.168.1.xxx
       端口:     xxxxx (动态, 不是 5555)
       配对码:   xxxxxx (6 位数字, 60 秒过期)
```

**记下这两个值, 60 秒内要在服务器输完。**

### 步骤 3: 服务器配对 + 连接

把上一步的 `IP 地址` 和 `端口` 替换下面命令:

```bash
export PATH="$HOME/android-platform-tools/platform-tools:$PATH"

# 1. 配对 (用配对端口, 不是 5555)
adb pair 192.168.1.xxx:<配对端口>
# 输入 6 位配对码
# 期望输出: "Successfully paired to 192.168.1.xxx:<配对端口>"

# 2. 连接 (走标准 5555, 配对后 cloudflared 自动允许)
adb connect 192.168.1.xxx:5555
# 期望输出: "connected to 192.168.1.xxx:5555"

# 3. 验证
adb devices
# 期望两行:
#   192.168.1.xxx:<配对端口>   device
#   192.168.1.xxx:5555         device
```

### 步骤 4: 第一次跑 Flutter (验证 hot reload)

```bash
cd ~/bbt-agent/flutter_app
flutter run -d 192.168.1.xxx:5555
```

看到 `Syncing files to device` → 等 30-60 秒首次编译 → 手机弹 暖客宝 应用 → **改一行代码按 `r` → 1 秒看到效果** → ✅ 配对成功。

---

## 日常使用 (配对一次, 永久有效)

**配对成功后**:
- 手机锁屏不影响 (WiFi 一直连)
- 手机重启后需重新 `adb connect 192.168.1.xxx:5555` (配对不需要重做)
- 服务器重启 / ADB 死了: 重连即可

**主人工作流**:
```bash
# 每天开工
./tools/dev-flutter.sh 192.168.1.xxx    # web + phone 并行

# 改代码 → 自动 hot reload (phone 终端按 r)
# 浏览器开 http://192.168.1.200:8080/ 看 web UI
```

---

## 防掉线 (可选, 主人拍)

如果手机经常断 (WiFi 抖动 / IP 变):

```bash
# 一键装 cron (每 2 分钟自动重连)
./tools/adb-watchdog.sh --install-cron 192.168.1.xxx
```

主人 cron 策略是 "Level 1 硬资产只保留备份", watchdog 类砍了。这个 adb-watchdog 是**开发期辅助** (主人自己在 dev 阶段用), 不是销售员服务, 不冲突。

---

## 常见坑

| 现象 | 解决 |
|------|------|
| `adb pair` 报 "Connection refused" | 配对码过期, 60 秒内要输完, 重来 |
| `adb connect` 后 `unauthorized` | 手机 USB 调试授权没勾, 重插 USB 重弹窗 |
| `connection reset` / 反复断 | 装 `--install-cron` 自动重连 |
| 改代码 hot reload 没反应 | 按 `R` 全量 restart |
| Flutter 找不到设备 | `adb devices` 看是否在线, `flutter devices` 看 flutter 认没认 |
| 改了 `pubspec.yaml` / 加插件 | `R` 不够, 需 Ctrl+C 重跑 `flutter run` |

---

## 验证清单

配对成功后, 跑这个端到端验证:

```bash
# 1. ADB 在线
adb devices | grep "192.168.1.xxx:5555.*device$"

# 2. Flutter 识别到设备
flutter devices | grep "192.168.1.xxx:5555"

# 3. 跑得起来 + hot reload 工作
cd ~/bbt-agent/flutter_app
flutter run -d 192.168.1.xxx:5555
# 等编译完, 手机弹 暖客宝
# 在 main.dart 加一行 debugPrint('test') → 终端按 r → 看手机 console 出现 'test'
```
