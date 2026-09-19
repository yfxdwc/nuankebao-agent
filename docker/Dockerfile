# ============================================
# 暖客宝 Next.js production image
# 多阶段构建, 镜像小, 启动快
# ============================================

# 阶段 1: 依赖
FROM node:20-alpine AS deps
RUN corepack enable && corepack prepare pnpm@9 --activate
WORKDIR /app
COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile

# 阶段 2: 构建
FROM node:20-alpine AS builder
RUN corepack enable && corepack prepare pnpm@9 --activate
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1

# ============================================
# 构建期占位 env (2026-09-19 P1)
#
# 根因: src/lib/db/index.ts / lib/crypto 在**模块加载时**校验 env;
#   `next build` 的 "Collecting page data" 会导入全部 route 模块 → 缺 env 必炸
#   (之前 Docker 构建卡在更早的 pnpm workspace 错, 从未走到这里)。
# 安全性: Next.js 只内联 NEXT_PUBLIC_*; 服务端 env 在运行时从容器环境读取,
#   这些占位值不会写入运行行为。真实值由 compose env_file (.env.prod) 注入。
# ============================================
ENV DATABASE_URL=postgres://build:build@127.0.0.1:5432/build
ENV AUTH_SECRET=build-time-placeholder-not-used-at-runtime
ENV PGCRYPTO_KEY=0000000000000000000000000000000000000000000000000000000000000000

RUN pnpm build

# 阶段 2.5: migration runner (compose tools profile)
# 说明: 运行阶段只有 standalone 产物 (无 tsx / drizzle / tools), migration 单独一个 target。
# 用法: docker compose -p nuankebao-prod -f docker-compose.prod.yml --env-file .env.prod \
#         run --rm migrate pnpm db:migrate
FROM deps AS migrate
# bash: check-migration-compat.sh 用 bash; findutils: 脚本用 GNU find -printf
#   (alpine BusyBox find 不支持 -printf, 会导致 compat 检查静默空跑 = 假通过)
RUN apk add --no-cache bash findutils
WORKDIR /app
COPY . .
CMD ["pnpm", "db:migrate"]

# 阶段 3: 运行
FROM node:20-alpine AS runner
RUN corepack enable && corepack prepare pnpm@9 --activate
WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

COPY --from=builder --chown=nextjs:nodejs /app/public ./public
# APK/应用版本显示 (P4): getAppVersion() 读 flutter_app/pubspec.yaml (如 0.2.3+4)
COPY --from=builder --chown=nextjs:nodejs /app/flutter_app/pubspec.yaml ./flutter_app/pubspec.yaml
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs
EXPOSE 3000
ENV PORT=3000
CMD ["node", "server.js"]