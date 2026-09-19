# modules/auth/ — 登录模块

> **架构定位** (per [ADR-0007](../../../docs/adr/0007-modular-architecture.md)): 暖客宝 APK 域的第一个业务模块 — **登录**.
> 实现方式 (2026-09-19 P2): **账号 / 手机号 + 密码** (邀请制, 不开放自助注册; 见 `docs/deploy/production-plan.md` §1.1).

## 入口

| 入口 | 文件 | 说明 |
|---|---|---|
| **登录页面** | `screens/login_screen.dart` | `LoginScreen` widget: 账号/手机号 + 密码 一步式 |
| **状态** | `core/providers/auth_provider.dart` (共享) | 当前登录用户 / loading / error 状态, 不在本模块内 |

## 依赖

- `core/theme/app_theme.dart` — 背景色 + 主色
- `core/providers/auth_provider.dart` — `ref.read(authProvider.notifier).login(identifier:, password:)`
- `core/http/api_client.dart` — 显示当前连接的后端地址 (诊断用)

## 流程

```
[账号/手机号] + [密码]
       ↓
ref.read(authProvider.notifier).login(identifier, password)
       ↓ native: Auth.js /auth/callback/credentials (identifier + password)
       ↓ web(dev): /api/auth/flutter-login (body 返回 session token, R12)
       ↓
ref.read(authProvider) → context.go('/customers')
```

后端校验: `src/lib/auth/credentials.ts` (username 或 phone_hash 查用户 + scrypt 校验 + 限流 5 次/分钟)。

## 扩展指南

**加"微信扫码登录"**:
1. 在 `screens/` 下新建 `wechat_login_screen.dart`
2. 在 `core/router/app_router.dart` 加路由 `/login/wechat`
3. 引入 `wechat_login_service` (放 `core/services/` 或本模块 `providers/`)

**短信 2FA / 找回密码 (Phase 2, 可选)**:
1. 后端加 `verification_code` 表 + 发码/校验接口 + 短信 adapter
2. 登录页在密码校验后加一步验证码 (或独立「找回密码」页)

## 测试

`tests/password.test.ts` (哈希/策略) + `tests/credentials.test.ts` (登录校验集成) 在仓库根 `tests/`。

## 关联文档

- [CHARTER §4.3 模块化规则](../../../docs/CHARTER.md#43-模块化规则-v013-新增)
- [AGENTS §4.5 模块化约束](../../../AGENTS.md#45-模块化约束-charter-43-模块化规则)
- [ADR-0007 §详细方案](../../../docs/adr/0007-modular-architecture.md)
- 生产方案: `docs/deploy/production-plan.md` §1.1/§3.B
