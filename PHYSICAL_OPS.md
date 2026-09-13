# 主人物理操作清单 (a/b/c)

> W10 完成后, **24 commits / 109 文件 / 59 测试** 已就绪
> 剩下 3 件事主人执行后, 项目即可"上生产 + 跑 Flutter + 真实 AI"

## A. Git Push (5 分钟)

### A.1 在 GitHub 创建 repo
1. 打开 https://github.com/new
2. 仓库名: `nuankebao-agent`(或你喜欢的)
3. **Private**(因为有健康数据, 不要 Public)
4. **不要**勾 "Initialize with README" (我们已有)
5. 点 "Create repository"
6. 复制 HTTPS 或 SSH URL (类似 `https://github.com/你的用户名/nuankebao-agent.git`)

### A.2 配 remote + push

```bash
cd /home/tooyan/nuankebao-agent

# 配 remote (替换为你的 URL)
git remote add origin https://github.com/你的用户名/nuankebao-agent.git

# 改默认分支 (可选)
git branch -M main

# 首次 push (会要求 GitHub 用户名 + Personal Access Token, 不要用密码)
# 建议先用 Personal Access Token: https://github.com/settings/tokens
git push -u origin master  # 或 main

# 之后 git push 就直接生效了
```

### A.3 验证
- 打开 GitHub repo, 应看到 24 commits
- Actions tab 应看到 CI 自动跑 (3 个 job: type-check / vitest / port-check)
- 3-5 分钟后 CI 全绿

---

## B. 装 Flutter SDK (30-60 分钟)

### B.1 下载 SDK (~700MB)

```bash
cd ~
curl -L -o flutter.tar.xz \
  https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.5-stable.tar.xz

# 解压
tar xf flutter.tar.xz

# 加到 PATH (永久)
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# 验证
flutter --version
# 应显示: Flutter 3.24.5 • channel stable
```

### B.2 装 Android Studio (可选, 用于 emulator + APK)

```bash
# Ubuntu/Debian
sudo snap install android-studio

# 或手动下载: https://developer.android.com/studio
# 启动后: More Actions → SDK Manager → 装 Android 11+ + Build Tools
```

### B.3 跑 暖客宝 Flutter app (端到端验证)

```bash
cd /home/tooyan/nuankebao-agent/flutter_app

# 装依赖
flutter pub get

# 生成 freezed 代码 (重要!)
dart run build_runner build --delete-conflicting-outputs

# 静态分析 (应 0 错误)
flutter analyze

# 跑 (需 Android emulator 启动 或 USB 真机)
flutter devices              # 看可用设备
flutter run -d emulator-5554 # 或你的设备 ID

# 验收 4 个核心流程:
# 1. 登录 (13800138000 + 123456)
# 2. 客户列表 → 新增客户
# 3. 养生记录 → 结构化表单 + 拍照
# 4. AI 助手 → 复购预测 + 效果分析

# 构建 APK (release)
flutter build apk --release
# 产物: build/app/outputs/flutter-apk/app-release.apk
```

### B.4 上架 Google Play (可选, W6 范围)

```bash
# 1. 注册 Google Play Console ($25 一次性)
# 2. 创建 app
# 3. 上传 AAB (不是 APK)
flutter build appbundle --release
# 4. 填资料 + 截图 + 隐私政策
# 5. 提交审核
```

### B.5 iOS (需要 macOS 机器)

Linux 不能 build iOS。需要:
- 借一台 Mac
- 装 Xcode + CocoaPods
- `cd ios && pod install`
- `flutter build ios --release`
- Xcode → Archive → TestFlight → App Store Connect

---

## C. 配 MiniMax API Key (10 分钟, 真实 AI)

### C.1 申请 key

1. 打开 https://api.minimaxi.com (或你的 MiniMax 平台)
2. 注册账号 → 实名认证
3. 创建 API Key (复制保存, 关页面就看不到了)
4. 注意: MiniMax 可能有不同平台 (MiniMax / MiniMax / 智谱), 看主人确认是哪个

### C.2 配 .env.local

```bash
cd /home/tooyan/nuankebao-agent
nano .env.local
# (或 vim / VSCode)

# 加这一行 (替换 <你的-key>):
MINIMAX_API_KEY=<你的-key>

# 已有就不用改:
# MINIMAX_API_BASE=https://api.minimaxi.com
# MINIMAX_MODEL=minimax-text-01

# 保存退出 (Ctrl+O, Enter, Ctrl+X for nano)
```

### C.3 重启 dev server

```bash
# 杀掉旧 dev
pkill -f "next dev --port 3003"

# 重启 (新 key 生效)
pnpm dev
```

### C.4 验证真实 AI (不是 mock)

```bash
# 登录
rm -f /tmp/cookies.txt
CSRF=$(curl -s -c /tmp/cookies.txt http://localhost:3003/api/auth/csrf | grep -oE '"csrfToken":"[^"]+"' | cut -d'"' -f4)
curl -s -b /tmp/cookies.txt -c /tmp/cookies.txt -X POST http://localhost:3003/api/auth/callback/credentials \
  -d "csrfToken=${CSRF}&phone=13800138000&code=123456" -o /dev/null

# 调 AI 端点
curl -s -b /tmp/cookies.txt -X POST http://localhost:3003/api/ai/follow-up \
  -H "Content-Type: application/json" -d '{"customerId":"1"}' | head -c 400

# 看 aiMock 字段:
# - true  = 走 mock 模板 (key 没读到)
# - false = 真实 AI 生成 (key 生效)
# - usage.promptTokens > 0 = 真实 token 消耗
```

### C.5 真实模式效果

- 客户画像: 基于 10 条养生知识 (RAG) + 客户记录 → 真实 AI 分析
- 跟进话术: 复购间隔 + 知识库话术 → 真实 AI 建议
- 复购预测: SQL 计算 (不调 AI, 但数字更准因为有更多历史)
- 效果分析: 多疗程数据 + 知识库 → 真实 AI 趋势分析

---

## 三个物理操作的时间线

```
Day 0  A. Git push (5 min)  ← 优先, 让 CI 跑起来
Day 0  C. MiniMax API (10 min)  ← 配真实 AI
Day 1  B. Flutter SDK + 跑 (60 min)  ← 端到端验证

之后:
- 浏览器手动验证 web 端 (按 docs/user-manual.md)
- 1-2 销售真用户内测 1 周
- 收集反馈 → 决定 Phase 2 / 3 路线
```

---

## 物理操作完成后的验证

主人做完后, 我能立即验证:
- ✅ git push → GitHub Actions CI 自动跑
- ✅ 装 Flutter → `flutter run` 端到端
- ✅ MiniMax key → `aiMock: false` + `usage.promptTokens > 0`

**所有验证都通过后, 告诉我"做完了", 我会:**
- 跑完整 `make test-all`
- 验证 Flutter 端 (编译/运行)
- 验证 AI 真实模式
- 开始 Phase 3 准备 (多租户 SaaS 化)

## 我现在能继续做的(不等主人物理)

- **W11**: pgvector schema 准备 + embedding API 客户端
- **W12**: 多租户架构 (SaaS 化 Phase 3 准备)
- **W13**: 限流持久化 (Upstash Redis 集成)
- **W14**: Sentry / 错误监控集成

任一个都不阻塞主人物理操作。