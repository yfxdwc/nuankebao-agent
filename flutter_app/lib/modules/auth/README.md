# modules/auth/ — 登录模块

> **架构定位** (per [ADR-0007](../../../docs/adr/0007-modular-architecture.md)): 暖客宝 APK 域的第一个业务模块 — **登录**.
> 实现方式: 手机号 + 验证码 (W1 mock, W2+ 接阿里云短信网关).

## 入口

| 入口 | 文件 | 说明 |
|---|---|---|
| **登录页面** | `screens/login_screen.dart` | `LoginScreen` widget, 手机号→验证码两步流程 |
| **状态** | `core/providers/auth_provider.dart` (共享) | 当前登录用户 / loading / error 状态, 不在本模块内 |

## 依赖

- `core/theme/app_theme.dart` — 背景色 + 主色
- `core/providers/auth_provider.dart` — `ref.read(authProvider.notifier).login(...)`
- `core/http/api_client.dart` — 显示当前连接的后端地址 (诊断用)

## 流程

```
[手机号] → 11 位校验 → [发送验证码] → mock (123456)
                                       ↓
                                  [验证码] → 6 位校验
                                       ↓
                              ref.read(authProvider.notifier).login(phone, code)
                                       ↓
                              ref.read(authProvider) → context.go('/dashboard')
```

## 扩展指南

**添加"微信扫码登录"**:
1. 在 `screens/` 下新建 `wechat_login_screen.dart`
2. 在 `core/router/app_router.dart` 加路由 `/login/wechat`
3. 引入 `wechat_login_service` (放 `core/services/` 或本模块 `providers/`)

**替换验证码服务 (W2+)**:
1. 在 `core/services/api.dart` 加 `requestSmsCode(String phone)` 方法
2. `screens/login_screen.dart` 的 `_sendCode()` 改为调用真实 API
3. mock 的 `123456` 改为后端返回

## 测试

无单测 (W2+ 加): 验证手机号校验逻辑 + 验证码流程 + 错误显示.

## 关联文档

- [CHARTER §4.3 模块化规则](../../../docs/CHARTER.md#43-模块化规则-v013-新增)
- [AGENTS §4.5 模块化约束](../../../AGENTS.md#45-模块化约束-charter-43-模块化规则)
- [ADR-0007 §详细方案](../../../docs/adr/0007-modular-architecture.md)
