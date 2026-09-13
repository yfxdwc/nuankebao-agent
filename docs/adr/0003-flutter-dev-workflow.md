# ADR-0003: Flutter 移动端开发工作流 (Web + Phone 并行)

> **状态**: ✅ Accepted (2026-09-05 主人拍板「并行」)
> **决策者**: 主人 (虾王)
> **背景**: BBT 移动端 (Flutter) 既要 UI 迭代快, 又要验 native 功能 (拍照/SQLite/推送/扫码)
> **对应元宪法**: [`CHARTER.md`](../CHARTER.md) §2 原则 3 移动优先 + §4.3 前端策略 apk-first + §5.2 必须 ask_user

---

## 1. 背景

BBT 销售员日常重度用手机 (Android), 移动端是核心交付物。但 Flutter 默认开发模式 (单设备 hot reload) 在 BBT 场景有 3 个痛点:

1. **UI 迭代慢**: 改一行 widget → 编译 → 手机屏闪 → 眼睛得在手机和编辑器之间切
2. **手机依赖**: 手机不在身边 (充电/被借走/锁屏) → 整个开发停摆
3. **native 验证盲区**: 拍照/SQLite/推送 Web 跑不了, 单 Phone 模式得真机调试

## 2. 决策

**采用 Web + Phone 并行方案, Web 为主, Phone 验 native。**

具体落地:

| 维度 | 决策 |
|------|------|
| 开发主战场 | Web (`flutter run -d web-server`) |
| Native 验证 | Phone (`flutter run -d <手机IP>:5555`) |
| 手机连接方式 | ADB 无线调试 (无线 WiFi, 装一次 APK) |
| 并行方式 | 两个 `flutter run` 进程 (终端 1 + 终端 2) |
| 启动封装 | `tools/dev-flutter.sh` 一键开两个 |
| IDE 集成 | VSCode `launch.json` compound 配置 |

## 3. 为什么不是单方案

### ❌ 纯 Phone
- 改一行 UI → 1-3 秒热重载 → 节奏慢 3 倍
- 手机不在身边 → 开发停摆
- 80% 工作是 UI/表单/列表, 不需要 native

### ❌ 纯 Web
- 拍照 / SQLite / 推送 / 扫码 → 跑不起来
- mock 写完还得在 Phone 跑一遍 → 等于干两遍
- 写到 native 调用就卡壳

### ✅ 并行 (Web 为主)
- Web 终端: UI 迭代秒刷新, DevTools 调试体验更好
- Phone 终端: native 验证, 改 native 代码按 `r` 秒看
- 默认盯 Web, 触发 native 验证切 Phone

## 4. 网络拓扑

```
主人 LAN (192.168.1.0/24)
├── 服务器 mini (192.168.1.200) ← Flutter SDK 在这里, 跑 flutter run
│   ├── 进程 1: flutter run -d web-server --web-port=8080
│   │   └── 浏览器访问 http://192.168.1.200:8080
│   └── 进程 2: flutter run -d 192.168.1.<手机IP>:5555
│       └── ADB 无线连接到手机
└── 主人手机 (192.168.1.<动态>)
    ├── USB 调试开启 (一次性)
    └── 无线调试 (Android 11+) 或 USB tcpip 配对 (一次性)
```

**关键约束**: 手机必须和服务器在同一 WiFi 网段 (192.168.1.x)。

## 5. 一次性配对流程

### 方式 A: 纯无线 (Android 11+, 推荐)

```
1. 手机: 开发者选项 → 无线调试 → 使用配对码配对设备
   → 屏幕显示 IP:PORT (如 192.168.1.10:37823) + 6 位配对码
2. 服务器:
   adb pair 192.168.1.10:37823  ← 输配对码
   adb connect 192.168.1.10:5555
3. 验证:
   adb devices  ← 应看到两行 (pair + connect)
```

### 方式 B: USB 配对一次

```
1. USB 连手机
2. 服务器:
   adb tcpip 5555
   adb shell ip route get 1.1.1.1 | awk '{print $7;exit}'  ← 拿 IP
3. 拔 USB
4. 服务器:
   adb connect 192.168.1.10:5555
```

配对完成 → **永远不重装 APK**, `flutter run -d IP:5555` 直接热重载。

## 6. 日常开发流程

### 启动

```bash
# 一键起两个 (默认 ./tools/dev-flutter.sh)
./tools/dev-flutter.sh                        # 只 web
./tools/dev-flutter.sh 192.168.1.10           # web + phone 并行
./tools/dev-flutter.sh 192.168.1.10 phone     # 只 phone
```

### 工作流

```
日常 80% 时间盯 Web 浏览器 (192.168.1.200:8080)
        ↓ 改代码 → 自动热重载 → 100ms 看到
        ↓
触发 native 验证 (拍照/SQLite/推送)
        ↓ 切到 phone 终端按 r
        ↓
发版前 → 装一次 APK 整体验收
```

### 快捷键 (两个终端通用)

| 键 | 作用 |
|----|------|
| `r` | Hot Reload (保留状态, 推荐) |
| `R` | Hot Restart (重置状态) |
| `q` | 退出 |
| `d` | Detach (后台跑, 改代码还能 reload) |

VSCode: 保存文件 = 自动 hot reload (绿色闪电图标需点亮)

## 7. 工具链

| 工具 | 路径 | 说明 |
|------|------|------|
| Flutter SDK | `~/flutter` | 不装到 /opt, 免 sudo |
| ADB (platform-tools) | `~/android-platform-tools/platform-tools` | 不装到 /usr, 免 sudo |
| PATH 配置 | `~/.bashrc` | 增量追加, 不覆盖 |
| adb-watchdog | `tools/adb-watchdog.sh` | 防手机断线自动重连 |
| dev-flutter | `tools/dev-flutter.sh` | 一键起 web + phone |
| launch.json | `flutter_app/.vscode/launch.json` | VSCode compound 启动 |

**安装原则**: 不动 /opt /usr (免 sudo), 全装到 ~/。

## 8. 验收节奏

| 阶段 | 主用 | 看哪 |
|------|------|------|
| 路由 / 状态管理 / 表单 | Web | 浏览器 |
| 列表 / 卡片 / 图表 | Web | 浏览器 |
| 调样式 / 像素对齐 | Web | 浏览器 DevTools |
| 接 API / 业务逻辑 | Web + Phone | 两个都盯 |
| 拍照 / 文件 / SQLite schema | Phone | 手机屏 |
| 推送 / 二维码 / 生物识别 | Phone | 手机屏 |
| 发版前整体验收 | Phone | APK 真机 |

## 9. 防掉线策略

WiFi 抖动 / 手机锁屏 / IP 变化 都会断 ADB 连接。两条腿:

1. **adb-watchdog cron**: 每 2 分钟检测重连
2. **phone 自动 IP 发现**: Phase 2 可加 mDNS / 固定 DHCP 租约

```bash
# 装 cron (一次性)
crontab -e
*/2 * * * * /home/tooyan/nuankebao-agent/tools/adb-watchdog.sh 192.168.1.10 >> /tmp/adb-watchdog.log 2>&1
```

## 10. 风险 & 缓解

| 风险 | 缓解 |
|------|------|
| 手机不在身边 | 纯 Web 也能跑 80% 功能 |
| 手机不在同 WiFi | Cloudflare Tunnel 反向暴露 ADB (Phase 2) |
| Web 与 Phone 行为不一致 | `--dart-define=ENV=dev` 区分 + native 必跑 Phone |
| Hot reload 卡住 (改 main.dart) | 按 `R` 全量 restart |
| Flutter SDK 升级 breaking | 锁版本 3.24.5, 升级走单独 ADR |

## 11. 后续演进

- **Phase 2**: Shorebird (dart 层 OTA, 上线后修 bug 免重装)
- **Phase 2**: Cloudflare Tunnel (远程开发, 手机和服务器不在同 WiFi)
- **Phase 3**: 多设备并行测试 (不同端口 5555/5556)
- **Phase 3**: Flutter Desktop (Linux build) 用于自动化测试

## 12. 参考

- [Flutter Hot Reload 文档](https://docs.flutter.dev/tools/hot-reload)
- [Android 无线调试](https://developer.android.com/tools/adb#wireless)
- BBT W1 实施文档: `docs/w1-implementation.md`
