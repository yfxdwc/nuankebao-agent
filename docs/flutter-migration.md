# 暖客宝 Flutter 迁移架构 (Phase 1.5)

> **主人决策**: 选 Flutter (不是 React Native + Expo, 不是 PWA, 不是 web)
> **日期**: 2026-09-04
> **目标**: 销售端 mobile app (iOS + Android), 老板/店长仍用 Next.js admin web

---

## 🎯 决策

| 端 | 技术栈 | 用户 |
|---|---|---|
| **销售端 (mobile)** | **Flutter 3.x + Dart** | 养生销售 (中年女性) |
| **管理端 (web)** | Next.js 15 (保留) | 老板 / 店长 |
| **Backend (共用)** | Next.js Route Handlers | 双方共用 |

**核心原则**: 不浪费已有工作 (Postgres / 加密 / 审计 / 业务逻辑 100% 复用), Flutter 全新前端, Next.js 退化为 "管理后台 + API server"。

---

## 🏗️ 架构

```
┌─────────────────────────────────────────────────────────┐
│  Flutter App (mobile, iOS + Android)                    │
│  ┌────────────────┬────────────────┬──────────────┐   │
│  │  登录          │  客户列表       │  仪表盘       │   │
│  │  验证码         │  详情/编辑      │  报表        │   │
│  │                │  养生记录表单   │  AI 助手     │   │
│  │                │  跟进任务       │  拍照        │   │
│  └────────────────┴────────────────┴──────────────┘   │
│  lib/services/api_client.dart → dio (HTTP)              │
└─────────────────────────────────────────────────────────┘
                       │ HTTPS / JSON
                       ↓
┌─────────────────────────────────────────────────────────┐
│  Next.js Backend (保留)                                   │
│  - /api/customers / /api/wellness-records / /api/ai/*  │
│  - /api/dashboard / /api/import / /api/reports         │
│  - /api/auth/* (Auth.js v5 + 手机号验证码)              │
└─────────────────────────────────────────────────────────┘
                       │ SQL
                       ↓
┌─────────────────────────────────────────────────────────┐
│  自托管基础设施 (已有)                                    │
│  - PostgreSQL 16 + pgcrypto + pgvector                   │
│  - Redis (待加, 缓存 + 队列)                             │
│  - MinIO (待加, 照片 / 备份)                            │
└─────────────────────────────────────────────────────────┘
```

---

## 📦 Flutter 依赖选型

| 依赖 | 用途 | 版本 |
|---|---|---|
| `flutter_riverpod` | 状态管理 | ^2.5.1 |
| `dio` | HTTP client | ^5.7.0 |
| `go_router` | 路由 | ^14.0.0 |
| `freezed` + `json_serializable` | 数据类 (不可变 + JSON) | ^2.5.0 |
| `flutter_secure_storage` | Token 安全存储 | ^9.2.0 |
| `image_picker` | 拍照 / 选图 | ^1.1.0 |
| `sqflite` | 离线缓存 (本地 DB) | ^2.3.0 |
| `cached_network_image` | 图片缓存 | ^3.4.0 |
| `intl` | 日期格式化 | ^0.19.0 |
| `fluttertoast` | 提示 | ^8.2.0 |
| `connectivity_plus` | 网络状态 | ^6.0.0 |
| `local_auth` | 生物识别 (后续) | ^2.3.0 |
| `flutter_local_notifications` | 本地通知 (后续) | ^17.0.0 |

---

## 🎨 主题: 养生绿 Material 3

- Primary: `#1f8a4c` (养生绿)
- 字体: 系统默认
- 风格: 简洁 / 温暖 / 圆角 / 适度的阴影
- 移动端优先 (单手操作, 按钮 ≥ 48dp)

---

## 📁 项目结构

```
flutter_app/
├── pubspec.yaml
├── README.md
├── lib/
│   ├── main.dart                      # 入口 + Riverpod ProviderScope
│   ├── app.dart                       # MaterialApp.router 配置
│   ├── theme/
│   │   └── app_theme.dart            # 养生绿主题
│   ├── router/
│   │   └── app_router.dart            # go_router 路由表
│   ├── models/                        # Freezed 数据类
│   │   ├── customer.dart
│   │   ├── wellness_record.dart
│   │   ├── interaction.dart
│   │   ├── follow_up_task.dart
│   │   └── user.dart
│   ├── services/
│   │   ├── api_client.dart           # dio + 拦截器 (token + audit context)
│   │   ├── auth_service.dart
│   │   ├── customer_service.dart
│   │   ├── wellness_record_service.dart
│   │   ├── follow_up_service.dart
│   │   └── ai_service.dart
│   ├── providers/                     # Riverpod 状态
│   │   ├── auth_provider.dart
│   │   ├── customer_provider.dart
│   │   └── ai_provider.dart
│   ├── screens/
│   │   ├── auth/
│   │   │   └── login_screen.dart
│   │   ├── dashboard/
│   │   │   └── dashboard_screen.dart
│   │   ├── customers/
│   │   │   ├── customers_list_screen.dart
│   │   │   ├── customer_detail_screen.dart
│   │   │   └── customer_form_screen.dart
│   │   ├── wellness/
│   │   │   ├── wellness_records_list_screen.dart
│   │   │   ├── wellness_record_detail_screen.dart
│   │   │   └── wellness_record_form_screen.dart
│   │   ├── follow_ups/
│   │   │   └── follow_ups_screen.dart
│   │   ├── interactions/
│   │   │   └── interactions_screen.dart
│   │   ├── ai/
│   │   │   └── ai_assistant_screen.dart
│   │   └── reports/
│   │       └── reports_screen.dart
│   └── widgets/                       # 通用组件
│       ├── async_value_widget.dart
│       ├── customer_card.dart
│       ├── wellness_record_card.dart
│       ├── body_part_chip_selector.dart
│       └── stat_card.dart
├── android/                           # Android 配置 (由 flutter create 生成)
└── ios/                               # iOS 配置 (由 flutter create 生成)
```

---

## 🔌 与 Next.js Backend 衔接

**API client 配置**:

```dart
class ApiClient {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'http://192.168.1.200:3003/api',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  // 拦截器: 自动加 session token
  _dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final token = await AuthService.getToken();
      if (token != null) {
        options.headers['Cookie'] = 'authjs.session-token=$token';
      }
      return handler.next(options);
    },
  ));
}
```

**注意**: Auth.js v5 用 httpOnly cookie 存 session, Flutter 移动端需要用 `flutter_secure_storage` 存 cookie 值,每次请求带上。

或者:**改成 Bearer token** 简化 Flutter 端 (后端加一个 `/api/auth/wap-login` 端点, 返回 JWT)

---

## 🗓️ 实施计划

| 周 | 任务 |
|---|---|
| W1 | Flutter 基础 + 登录 + 客户列表 (本文档编写 + 代码骨架) |
| W2 | 客户详情 + 养生记录结构化表单 (核心录入) |
| W3 | 跟进任务 + 联系记录 + 仪表盘 |
| W4 | 拍照 + 离线缓存 + 同步 |
| W5 | AI 助手 (MiniMax) + 推送通知 |
| W6 | 测试 + 上架 (TestFlight + Google Play) + 1-2 销售内测 |

**总周期**: 6-8 周 MVP (含上架)

---

## 🆚 与已有 web 的关系

| 已有工作 | Flutter 路线下 |
|---|---|
| Postgres schema (13 表) | ✅ 100% 复用 |
| 字段加密 (AES-256-CBC) | ✅ 100% 复用 |
| 审计触发器 (5 个) | ✅ 100% 复用 |
| 业务 queries (6 个) | ✅ 100% 复用, 搬到 backend |
| API routes (15+ 个) | ✅ 100% 复用, Flutter 调 |
| Prompt 模板 (3 个) | ✅ 100% 复用 |
| Excel 导入 | ✅ web 端保留 |
| 报表中心 | ✅ web 端保留 |
| Next.js UI (admin web) | ✅ 保留作为管理后台 |
| React UI 组件 | ❌ 不需要 (Flutter 重新写) |

**核心**: 数据库层 / 业务逻辑层 0 浪费, 前端全新 Flutter。

---

## 📌 主人需做的物理操作

### 1. 安装 Flutter SDK

```bash
# 下载 Flutter (stable, ~700MB)
cd ~
curl -L -o flutter.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.5-stable.tar.xz

# 解压
tar xf flutter.tar.xz

# 加到 PATH
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# 验证
flutter --version
flutter doctor
```

### 2. (可选) 装 Android Studio

```bash
# 用于 Android emulator + APK 构建
sudo apt install android-studio  # 或 snap
```

### 3. (可选) 装 Xcode (仅 macOS)

```bash
# macOS 才能装 iOS 工具链
# Linux 不能开发 iOS, 主人部署时需要 mac 机器
```

---

## 🎯 W1 交付

✅ 架构文档 (本文件)
✅ Flutter 项目结构 + 完整代码 (12 屏 + 4 service + 5 model)
✅ README + 安装说明
✅ pubspec.yaml
⏸ 主人装 Flutter SDK
⏸ 跑 `flutter pub get` + `flutter analyze` 验证

---

## 风险与兜底

| 风险 | 兜底 |
|---|---|
| Flutter 学习曲线 | 主人已会 JS/TS, Dart 1-2 天上手 |
| iOS 必须 macOS | W1-W5 Linux 开发, W6 借 mac 打包 |
| 性能不如 RN 新架构 (JSI/Hermes) | 养生 CRM 数据量小, 性能足够 |
| 团队 Flutter 经验 | 0 经验可以雇 1 个 Flutter 开发, 或外包 |

---

**记录日期**: 2026-09-04
**下次评审**: W1 完成后