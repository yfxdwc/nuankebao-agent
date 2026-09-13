# 暖客宝 Flutter App (移动端)

> 暖客宝 · 大健康行业销售 CRM 移动端 (iOS + Android)
> 后端: 暖客宝 Next.js (复用, 见 `../docs/flutter-migration.md`)

## 状态

**W1 骨架完成** (2026-09-04) + **Flutter 环境就绪** (2026-09-05)

✅ 已完成:
- pubspec.yaml + 依赖
- 主题 (养生绿 Material 3)
- 路由 (go_router)
- API client (dio + Auth.js cookie)
- 5 个 service (auth / customer / wellness / follow-up / ai / dictionary)
- 5 个 model (freezed)
- 3 个 provider (auth + service providers)
- 12 个 screen (登录/客户/养生记录/跟进/联系/AI/报表)
- 1 个 widget (stat card)
- **Flutter SDK 3.24.5 装好** (`~/flutter`, PATH 已配)
- **ADB 装好** (`~/android-platform-tools/platform-tools`)
- **Android SDK 35 + Chrome + 4 platform 全部 doctor 绿**
- **Web + Phone 并行开发工作流** (ADR-0003, Web 为主, Phone 验 native)
- web + linux 平台已 enable (`flutter create --platforms=web,linux .`)
- flutter analyze: 21 lint warning, 0 error
- web-server release mode smoke test: HTTP 200, main.dart.js 2.7MB OK

## 开发 (Web + Phone 并行, 详见 `../docs/adr/0003-flutter-dev-workflow.md`)

```bash
# 一键起开发环境 (从 bbt-agent/ 根目录)
./tools/dev-flutter.sh                        # 只 web (浏览器秒刷新)
./tools/dev-flutter.sh 192.168.1.<手机IP>     # web + phone 并行
./tools/dev-flutter.sh 192.168.1.<手机IP> web # 只 phone
```

浏览器打开 `http://192.168.1.200:8080/` 看 Web UI (release 模式)。

手机第一次连 (一次性):
```bash
# 手机开发者选项 → 无线调试 → 配对码配对 → 拿到 IP:PORT
adb pair 192.168.1.<手机IP>:<配对端口>     # 输 6 位配对码
adb connect 192.168.1.<手机IP>:5555
adb devices                                  # 应看到 device
```

日常开发:
```bash
cd flutter_app
flutter pub get                              # 装依赖 (首次)
dart run build_runner build --delete-conflicting-outputs  # freezed 代码生成
flutter analyze                              # 静态检查

# 看可用设备
flutter devices
# Linux • linux-x64
# Chrome • web-javascript
# <手机IP>:5555 • android-arm64 (无线连上后)

# 单独跑
flutter run -d web-server --web-port=8080
flutter run -d 192.168.1.<手机IP>:5555

# VSCode 用户: F5 选 "3. 🔄 Web + Phone (compound)"
```

### Flutter 工具链自检 (新机器跑)

```bash
source ~/.bashrc
flutter --version    # 期望 3.24.5
adb version          # 期望 1.0.41+
flutter doctor       # 期望 Android toolchain + Chrome 都绿
```

## 故障排查 (Flutter 环境)

| 现象 | 解决 |
|------|------|
| `flutter: command not found` | `source ~/.bashrc` 或 `export PATH=$HOME/flutter/bin:$PATH` |
| `cmdline-tools missing` | `source ~/.bashrc` (ANDROID_HOME 已配) |
| Web-server 启动后浏览器白屏 | 等 30-60 秒编译 dart→JS, 或用 `-d chrome` (需 GUI) |
| ADB 连不上手机 | 手机和服务器同 WiFi? 手机开了无线调试? 防火墙挡 5555? |
| Phone 模式 `unauthorized` | 手机屏幕弹「允许 USB 调试」框, 勾「总是允许」 |
| Hot reload 无效 | 按 `R` 全量 restart; 改了 main.dart import 也得 R |
| WiFi 抖动断连 | `./tools/adb-watchdog.sh <手机IP>` 重连, 或装 cron 每 2 分钟自动跑 |

详见 `../docs/adr/0003-flutter-dev-workflow.md` §9 (防掉线) + §6 (日常流程)。

## 后端地址配置 (--dart-define)

`lib/services/api_client.dart` 用 `--dart-define` 注入, 编译时生效:

```bash
# 局域网测试 (默认值, 不传 define 就是它)
flutter build apk --release

# 公网 (经 cloudflare tunnel → 本机 3003)
flutter build apk --release --dart-define=NUANKEBAO_API_BASE=https://nuankebao.tooyang.top/api
```

⚠️ **base URL 必须以 `/api` 结尾**: dio 拼 URL 是字符串拼接 (baseUrl + path),
各 service 的 path 都以 `/` 开头且不含 `/api`, define 只给 origin (漏了 `/api`) 时
所有请求都会 404 (W14 踩过的坑)。`normalizeApiBaseUrl` 会兜底补 `/api`, 但请按上面写全。

本机 (192.168.1.200) 构建环境: 需 JDK 17 (`JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64`, 21 缺 jlink 会编译失败)。

## 架构

- **状态**: Riverpod 2
- **路由**: go_router 14
- **HTTP**: dio 5 (拦截器自动加 session token)
- **数据类**: freezed 2.5 (不可变 + JSON)
- **安全存储**: flutter_secure_storage (token)
- **离线**: sqflite (W4 实施)
- **拍照**: image_picker (W4 实施)

## 目录结构

```
flutter_app/
├── pubspec.yaml
├── README.md
├── lib/
│   ├── main.dart                       # 入口
│   ├── app.dart                        # MaterialApp.router
│   ├── theme/app_theme.dart            # 养生绿主题
│   ├── router/app_router.dart          # go_router
│   ├── models/                         # freezed 数据类
│   ├── services/                       # 业务 service
│   ├── providers/                      # Riverpod providers
│   ├── screens/                        # 12 个页面
│   │   ├── auth/login_screen.dart
│   │   ├── dashboard/dashboard_screen.dart
│   │   ├── customers/
│   │   ├── wellness/
│   │   ├── follow_ups/
│   │   ├── interactions/
│   │   ├── ai/
│   │   └── reports/
│   └── widgets/stat_card.dart
├── android/                            # Android 配置 (flutter create 生成)
├── web/                                # Web 平台 (flutter create 生成, ADR-0003)
├── linux/                              # Linux 平台 (flutter create 生成, ADR-0003)
└── .vscode/launch.json                 # VSCode F5 compound 配置 (ADR-0003)
```

## 关键设计

1. **后端 100% 复用**: 调 Next.js API (无重写)
2. **会话用 Auth.js cookie**: dio 拦截器维护极简 cookie jar —— 登录时把服务端
   Set-Cookie 的 csrf / session cookie 原样收下并带回 (csrf 不回带会 MissingCSRF,
session 名错了会 401, 见 `lib/services/api_client.dart` 注释)
3. **手机优化**: 按钮 ≥ 48dp, 单手操作, Material 3
4. **Bottom Navigation**: 5 个主 tab (仪表盘/客户/养生/跟进/AI)
5. **Web + Phone 并行开发**: ADR-0003 — Web 写 UI, Phone 验 native

## 已知 TODO

- [ ] iOS 配置 (需要 macOS + Xcode)
- [ ] Android release 签名
- [ ] 推送通知 (firebase_messaging)
- [ ] 离线缓存 (sqflite)
- [ ] 拍照上传 (image_picker + MinIO 后端)
- [ ] 国际化 (中文 OK, 英文 W2)

## 路线图

| 周 | 内容 |
|---|---|
| W1 (完成) | 骨架 + 登录 + 客户列表 + 开发环境 (本 README 范围) |
| W2 | 客户详情 + 养生记录表单 (结构化录入) |
| W3 | 跟进任务 + AI 助手完善 |
| W4 | 拍照 + 离线缓存 |
| W5 | 推送通知 + 生物识别 |
| W6 | 上架 (TestFlight + Google Play) + 内测 |

详见 `../docs/flutter-migration.md` 和 `../docs/adr/0003-flutter-dev-workflow.md`。
