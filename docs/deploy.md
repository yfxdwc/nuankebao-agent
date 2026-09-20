# 暖客宝 部署完整指南

> **2026-09-19 起**: 生产部署请先看
> [`docs/deploy/production-plan.md`](deploy/production-plan.md)（v2：tc 本机 Docker 隔离 + 账号密码登录；含未来腾讯云迁移参考）。
> 本文件仍是通用部署手册与命令参考。

> 目标: 把 暖客宝 部署到主人自有物理服务器 (Debian 12 / Ubuntu 22.04)
> 适用: 主人 1-1 部署, 不假设有运维经验

## tc 本机 Docker 隔离生产栈 (2026-09-19, 当前生产)

> 完整方案: [`docs/deploy/production-plan.md`](deploy/production-plan.md)
>
> dev = `next dev` :3003 (保持不动)；prod = Docker 栈 :3004 (只绑 127.0.0.1，公网走 cloudflared)。
> 两边容器/数据卷/端口/备份目录全部独立。

**常用命令**:

| 操作 | 命令 |
|---|---|
| 部署/更新 prod | `bash deploy/prod-deploy.sh` |
| 看容器状态 | `docker compose -p nuankebao-prod -f docker-compose.prod.yml --env-file .env.prod ps` |
| 看日志 | `docker compose -p nuankebao-prod -f docker-compose.prod.yml --env-file .env.prod logs -f web` |
| 手动重启 prod web | `docker restart nuankebao-prod-web` |
| 停/起 prod 栈 | `sudo systemctl stop/start nuankebao-stack.service` (开启机自启) |
| 手动备份 (PG+媒体) | `systemctl --user start nuankebao-prod-backup.service` |
| 备份日志 | `tail -f /home/tooyan/nuankebao-databackups/prod/logs/backup.log` |
| 健康检查 | `systemctl --user status nuankebao-prod-healthcheck.service` (每 5 分钟) |
| 建档/重置密码 | `docker compose -p nuankebao-prod -f docker-compose.prod.yml --env-file .env.prod run --rm --no-deps -e ADMIN_USERNAME=admin -e ADMIN_PASSWORD='...' -e ADMIN_PHONE=19957347866 migrate pnpm db:ensure-admin`（脚本已合并: 一个入口管建档/提权/重置密码/补档案, 见 §7.5） |
| 批量建号 (邀请制) | 同上把脚本换成 `pnpm tsx scripts/import-users.ts users.csv` |
| 更新 APK | 拷到 `data/prod/downloads/NUANKEBAO-release.apk` (compose `:ro` 挂载, 无需重建镜像) |
| 首次/重装 systemd units | `bash deploy/install-systemd.sh` |

**红线**:

- `.env.prod` 权限 600、不进 git；**严禁** 写 `DEV_SKIP_AUTH` / `DEV_LOGIN_ANY_USER`
- prod 端口只绑 `127.0.0.1:3004`，不要改成 `0.0.0.0`；**公网入口 = `nuankebao.tooyang.top` → :3004**
  （dev = `nuankebao-dev.tooyang.top` → :3003；2026-09-20 P5 切换）
- 改域名/证书前先看 production-plan §4 强绑定三件套 (hostname / AUTH_URL / APK base URL)
- 备份/恢复: `NUANKEBAO_PROFILE=prod` 隔离目录 (`nuankebao-databackups/prod/`)，不要手动指定 dev 路径覆盖

## 0. 准备工作

### 0.1 硬件要求

| 组件 | 最低 | 推荐 |
|---|---|---|
| CPU | 2 核 | 4 核+ |
| 内存 | 2 GB | 4 GB+ |
| 硬盘 | 20 GB | 50 GB+ SSD |
| 网络 | 10 Mbps | 100 Mbps |

### 0.2 系统要求

- Debian 12 (bookworm) 或 Ubuntu 22.04 LTS
- root 权限
- 公网 IP 或内网穿透 (frp / cloudflare tunnel)

### 0.3 域名 (可选,推荐)

- 阿里云 / 腾讯云 / Cloudflare 解析
- `nuankebao.tooyang.top` 指向服务器 IP

---

## 1. 初始环境

### 1.1 SSH 登录

```bash
ssh root@your-server-ip
```

### 1.2 创建专用用户

```bash
# 创建 nuankebao 用户
useradd -m -s /bin/bash nuankebao
# 加 sudo 权限 (可选, 简化部署)
echo "nuankebao ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/nuankebao
# 切换到 nuankebao
su - nuankebao
```

### 1.3 装基础工具

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git openssl gnupg2 rsync nginx certbot python3-certbot-nginx
```

### 1.4 装 Docker

```bash
# Docker 官方脚本
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker nuankebao
newgrp docker

# 验证
docker --version
docker compose version
```

### 1.5 装 Node.js (备选, 仅 Flutter 端需要)

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
sudo npm install -g pnpm
node --version  # 应该 >= 20
pnpm --version
```

### 1.6 防火墙

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status
```

⚠️ 端口 5432 (Postgres) **不要对外开放**。

---

## 2. 部署 暖客宝 后端

### 2.1 拉代码

```bash
# 创建部署目录
sudo mkdir -p /opt/nuankebao
sudo chown nuankebao:nuankebao /opt/nuankebao
cd /opt/nuankebao

# 拉代码 (用 git bundle, 主人本地先打包)
# 主人本地: git bundle create nuankebao.bundle --all
# 传: scp nuankebao.bundle nuankebao@server:/opt/nuankebao/
# 服务器: git clone nuankebao.bundle nuankebao
```

或直接 git clone:
```bash
git clone https://github.com/your-org/nuankebao-agent.git
cd nuankebao-agent
```

### 2.2 装依赖

```bash
pnpm install --frozen-lockfile
```

### 2.3 生成密钥

```bash
# Postgres 密码
POSTGRES_PASSWORD=$(openssl rand -hex 16)
echo "POSTGRES_PASSWORD: $POSTGRES_PASSWORD"

# Auth.js secret
AUTH_SECRET=$(openssl rand -base64 32)

# 字段加密密钥 (32 bytes hex)
PGCRYPTO_KEY=$(openssl rand -hex 32)

# 备份密码 (主人选个能记住的)
BACKUP_PASSPHRASE="你的备份密码_至少16位"

# 保存到文件 (权限 600)
cat > .env << EOF
POSTGRES_USER=nuankebao
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=nuankebao
APP_PORT=3003
AUTH_URL=https://nuankebao.tooyang.top
AUTH_SECRET=${AUTH_SECRET}
PGCRYPTO_KEY=${PGCRYPTO_KEY}
BACKUP_PASSPHRASE=${BACKUP_PASSPHRASE}
EOF

chmod 600 .env
```

### 2.4 启动 Docker

```bash
docker compose up -d postgres
docker compose ps   # 应看到 nuankebao-postgres healthy
```

### 2.5 初始化数据库

```bash
# 应用 schema + 触发器
pnpm db:migrate

# 灌入字典数据 (9 个身体部位 + 8 个服务项目 + 8 个耗材)
pnpm db:seed

# 验证
docker exec nuankebao-postgres psql -U nuankebao -d nuankebao -c "\dt"
# 应看到 13 个表
```

### 2.6 构建 + 启动 Web

```bash
# 构建镜像
docker compose build web

# 启动
docker compose up -d
docker compose ps   # 应看到 nuankebao-postgres + nuankebao-web 都 healthy
```

### 2.7 验证

```bash
# 健康检查
curl http://localhost:3003/api/health
# 应返回 {"status":"healthy","checks":{"db":"ok"}}

# 检查日志
docker compose logs -f web
```

---

## 3. Nginx 反向代理 + HTTPS

### 3.1 创建 Nginx 配置

```bash
sudo tee /etc/nginx/sites-available/nuankebao << 'EOF'
server {
    listen 80;
    server_name nuankebao.tooyang.top;

    # 强制 HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name nuankebao.tooyang.top;

    # SSL 证书 (Let's Encrypt)
    ssl_certificate /etc/letsencrypt/live/nuankebao.tooyang.top/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/nuankebao.tooyang.top/privkey.pem;

    # 性能
    client_max_body_size 20M;  # 支持照片上传

    # 反代
    location / {
        proxy_pass http://127.0.0.1:3003;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;
    }

    # 静态资源 (照片直接 nginx 服务, 减轻 web 压力)
    location /uploads/ {
        alias /opt/nuankebao/public/uploads/;
        expires 7d;
        access_log off;
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/nuankebao /etc/nginx/sites-enabled/
sudo nginx -t
```

### 3.2 申请 SSL 证书

```bash
sudo certbot --nginx -d nuankebao.tooyang.top --email your@email.com
# 按提示完成, certbot 会自动改 nginx 配置
```

### 3.3 重启 Nginx

```bash
sudo systemctl restart nginx
```

### 3.4 验证 HTTPS

```bash
# 应自动跳转 https://
curl -I http://nuankebao.tooyang.top

# 应返回 200
curl -I https://nuankebao.tooyang.top/api/health
```

---

## 4. 备份策略

### 4.1 首次跑备份

```bash
# 必须设置 BACKUP_PASSPHRASE 环境变量 (从 .env 读)
export BACKUP_PASSPHRASE="你的备份密码"

# 手动跑一次 (验证脚本工作)
./tools/backup.sh

# 验证
ls -lh /opt/nuankebao/backups/
# 应看到 backup-20260101-030000.tar.gpg
```

### 4.2 配置 cron 每日自动跑

```bash
crontab -e
# 加这一行 (每天凌晨 3 点):
0 3 * * * BACKUP_PASSPHRASE="你的密码" /opt/nuankebao/tools/backup.sh >> /var/log/nuankebao-backup.log 2>&1
```

### 4.3 异地同步 (强烈建议)

```bash
# 安装 rclone (支持 S3 / 阿里云 OSS / 腾讯云 COS / Google Drive)
curl https://rclone.org/install.sh | sudo bash

# 配置 (按 rclone wizard)
rclone config

# 同步 (每日 4 点, 备份后 1 小时)
crontab -e
0 4 * * * rclone sync /opt/nuankebao/backups/ remote:nuankebao-backups/ --log-file=/var/log/nuankebao-rclone.log
```

### 4.4 演练恢复 (每季度)

```bash
# 选最近的备份测试
sudo ./tools/restore.sh /opt/nuankebao/backups/backup-20260101-030000.tar.gpg

# 验证数据完整性
docker exec nuankebao-postgres psql -U nuankebao -d nuankebao -c "SELECT COUNT(*) FROM customer;"
curl http://localhost:3003/api/health
```

详见 `tools/SOP.md`。

---

## 5. 监控

### 5.1 健康检查脚本 (每日)

```bash
# /opt/nuankebao/tools/health-check.sh
#!/bin/bash
HEALTH=$(curl -s http://localhost:3003/api/health | grep -o '"db":"ok"')
if [ -z "$HEALTH" ]; then
  echo "⚠️  暖客宝 不健康, 立即排查"
  # TODO: 飞书 / 邮件告警
  exit 1
fi
```

### 5.2 磁盘监控

```bash
# 备份到 /var/log/disk-usage.log (cron 每周跑)
0 0 * * 0 df -h > /var/log/disk-usage.log
```

### 5.3 飞书告警 (可选)

详见 `tools/SOP.md` §告警集成。

---

## 6. 升级流程

```bash
# 1. 拉新代码
cd /opt/nuankebao
git pull origin master

# 2. 装新依赖
pnpm install --frozen-lockfile

# 3. 跑新 migration (如有)
pnpm db:migrate

# 4. 重新构建 + 重启 (零停机可用 docker compose up -d --no-deps --build web)
docker compose build web
docker compose up -d --no-deps web

# 5. 验证
curl https://nuankebao.tooyang.top/api/health
```

### 6.1 Migration 回滚 SOP (跑挂了怎么办)

> **背景**: CHARTER §3.5 规定 `pnpm db:migrate` 创破坏性 migration 必带 `drizzle/down/<同名>.sql`。本节讲怎么用。
> **前提**: W3 之前所有 migration 都是加表 / 加列 (纯加性), **不需要 down**。加 down 是 W3+ 破坏性 migration 才有。

```bash
# 1. 查看最近 n 条 migration (从 drizzle/meta/_journal.json 读 idx)
cat drizzle/meta/_journal.json | jq '.entries[-3:]'
# 输出形如:
#   {"idx": 2, "tag": "0002_wellness_knowledge", ...}
#   {"idx": 3, "tag": "0003_xxx", ...}

# 2. 检查要回滚的 migration 有没有 down.sql
ls drizzle/down/<tag>.sql
# 例: ls drizzle/down/0003_xxx.sql
# 缺 = 可能是加性 migration (不需要 down), 或作者漏写 (问 agent / 看 ADR)

# 3. 跑回滚 (单步)
pnpm db:migrate:down <idx>
# 例: pnpm db:migrate:down 3
# 会读 drizzle/down/0003_xxx.sql 并执行 (事务包走)

# 4. 验证
docker exec nuankebao-postgres psql -U nuankebao -d nuankebao -c "\dt"
docker exec nuankebao-postgres psql -U nuankebao -d nuankebao -c "\d <table_name>"

# 5. 如 migration 跑挂了一半 (db:migrate 中间错), 手动修复:
docker exec nuankebao-postgres psql -U nuankebao -d nuankebao
# 查 __drizzle_migrations 表看哪些 migration 被标记为已跑
SELECT * FROM drizzle.__drizzle_migrations ORDER BY id;
# 如需手工改, 看具体 migration 是不是脏状态, 必要时跳过 (但请记 ADR)
```

**什么时候需要回滚**:
- ❌ migration 跑挂 (脚本错误 / NOT NULL 冲突 / 锁超时)
- ❌ 上线后发现破坏性 migration 误用 (DROP 错了表)
- ❌ 测试环境调试反悔

**什么时候不需要回滚**:
- ✅ migration 跑成功但应用代码不兼容 → 回代码, 不回 DB
- ✅ 加表 / 加列 (纯加性) → 后期反转是 "加个 DROP COLUMN migration", 不是 down

**预防**:
- W3 起任何 migration 必跑 `pnpm db:compat` (CI 阻断)
- 破坏性 migration 必配 down.sql (本地手跑一遍确认不报错)
- W5 内测前 拉测试库反复跑 `db:migrate` + `db:migrate:down` 演练

---

## 7. 灾难恢复

### 7.1 数据库损坏

```bash
# 停止 web
docker compose stop web

# 从最新备份恢复
./tools/restore.sh /opt/nuankebao/backups/backup-XXX.tar.gpg

# 启动 web
docker compose up -d web

# 验证
curl https://nuankebao.tooyang.top/api/health
```

### 7.2 服务器整机坏

```bash
# 1. 新机器, 重复 §1-§3 步骤
# 2. 从异地 (rclone) 拉备份
rclone sync remote:nuankebao-backups/ /opt/nuankebao/backups/

# 3. 跑恢复
cd /opt/nuankebao
./tools/restore.sh /opt/nuankebao/backups/backup-XXX.tar.gpg

# 4. 启动
docker compose up -d
```

### 7.3 密钥泄露

```bash
# 立即重置所有密钥
NEW_PASSWORD=$(openssl rand -hex 16)
NEW_PGCRYPTO_KEY=$(openssl rand -hex 32)
NEW_AUTH_SECRET=$(openssl rand -base64 32)

# 更新 .env
sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${NEW_PASSWORD}|" .env
sed -i "s|PGCRYPTO_KEY=.*|PGCRYPTO_KEY=${NEW_PGCRYPTO_KEY}|" .env
sed -i "s|AUTH_SECRET=.*|AUTH_SECRET=${NEW_AUTH_SECRET}|" .env

# 重置 Postgres
docker compose down postgres
docker volume rm nuankebao-agent_nuankebao-postgres-data
# ⚠️  这一步会清空 DB, 确保有备份
docker compose up -d postgres
pnpm db:migrate
pnpm db:seed

# 重置加密字段 (W3 后端添加 re_encrypt 工具)
# 详见 docs/security-compliance.md §密钥轮换
```

---

## 7.5 系统管理员账号 (长期保留, 主人 2026-09-19 拍)

> 主人原话: 「长期保留系统管理员账号 admin，生产环境也要保留」
> → 管理员账号是**永久设施**: dev 机器 + 生产环境都必须存在一个 `role='admin'` 账号。
>   (`user.role` enum: `admin | manager | sales`, 默认 `sales`)

**为什么必须保留**（业务依赖）:
- 加盟落位「三方确认」: 只有**已加盟用户**或**系统管理员**能设置加盟
- 系统管理员设置加盟**免多方确认**（直接落位, `verified_by='admin'`）+ 可全网任意点位
- 没有管理员账号 → 没人能兜底修图谱 / 强制解除加盟 / 给人补加盟

**保证手段**（幂等脚本）:

```bash
# dev 机器 (默认 13800138000)
pnpm db:ensure-admin

# 生产环境: **生产管理员手机号 = 19957347866** (主人 2026-09-19 拍)
ADMIN_PHONE=19957347866 ADMIN_NAME=管理员 pnpm db:ensure-admin
# 或
npx tsx scripts/ensure-admin.ts --phone=19957347866 --name=管理员
```

> 📌 **生产管理员账号**: 手机号 `19957347866`, 姓名 `管理员`, `role='admin'`。
> 该手机号同时写在 `.env.example` 的 `ADMIN_PHONE` 里, 部署时 `.env` 直接带上即可。

行为:
- 账号不存在 → 建一个 (`role='admin'`, 无加盟商绑定, `is_active=true`)
- 账号已存在 → **只把 role 抬成 admin**, 不覆盖姓名 / 加盟商绑定 / 其他字段
- 打印最终 `id / 手机号(掩码) / 姓名 / role`

**部署清单里必须勾**:
- [ ] 生产部署后跑一次 `ADMIN_PHONE=19957347866 ADMIN_NAME=管理员 pnpm db:ensure-admin`
- [ ] 灾备恢复 (`restore_verify` / 换机器) 后再跑一次 —— 恢复的备份里如果缺管理员, 这里补上
- [ ] 记录的 `ADMIN_PHONE` 写进密钥库 / 部署笔记（下一个维护者要能找到）

**登录方式**:
- dev: `POST /api/auth/flutter-login` (`code=123456`) 或 `/login`
- 生产: 短信验证码登录（管理员账号同样走手机号验证码）

**安全提醒**:
- 管理员账号**不要**绑定加盟商身份用于日常业务（保持"管理"与"业务"分离更清晰；
  当前 dev 账号 13800138000 既是 admin 又绑了加盟商 75, 属于测试便利, 生产建议分开）
- 生产环境务必 `unset DEV_SKIP_AUTH` / 不设 `DEV_LOGIN_ANY_USER`, 否则手机号验证码形同虚设

## 8. 完整清单 (主人部署后勾选)

- [ ] 服务器初始 (用户 / 防火墙 / Docker)
- [ ] 代码拉取
- [ ] pnpm install
- [ ] 密钥生成 + .env 配置
- [ ] Postgres 启动 + 健康
- [ ] db:migrate + db:seed
- [ ] Web 镜像构建 + 启动
- [ ] /api/health 200
- [ ] Nginx 反代配置
- [ ] SSL 证书 (Let's Encrypt)
- [ ] HTTPS 验证
- [ ] 备份脚本首次跑
- [ ] cron 配置
- [ ] rclone 异地同步
- [ ] 恢复演练 (至少 1 次)
- [ ] 健康监控脚本
- [ ] 飞书 / 邮件告警 (可选)

完成后, 暖客宝 正式上线!

---

**详细运维流程**: `tools/SOP.md`
**用户使用手册**: `docs/user-manual.md`

---

## APK 签名 (升级不掉登录的前提)

> 背景: 主人 2026-09-21 问「升级 app 后能保持登录状态吗」。**能不能保持, 取决于签名密钥是否一致**。

Android 只允许**同一签名**的包覆盖安装:

| 情况 | 结果 |
|---|---|
| 同包名 + 同签名, 直接装 (不卸载) | ✅ 升级成功, app 数据保留 → **登录状态保持** (会话 10 年, 见 ADR-0013) |
| 签名不同 (例如误用 debug 签名) | ❌ 安装失败 "应用未安装"; 必须先卸载 → **登录状态 + 本地缓存全丢** |
| 先卸载再装 (任何情况) | ⚠️ 同上, 数据丢失 (服务端数据仍在, 重新登录即可恢复) |

### 签名材料 (本机现状)

| 项 | 值 |
|---|---|
| 包名 | `cn.nuankebao.app` |
| keystore | `/home/tooyan/nuankebao-keys/nuankebao-release.jks` (chmod 600, **务必备份**) |
| 配置 | `flutter_app/android/key.properties` (含密码, 不入 git) |
| 证书 | `CN=NuankeBao, OU=Mobile, O=NuankeBao` |
| SHA-256 | `0D:B0:A1:BC:FF:6D:A7:03:B9:FE:3A:3C:05:03:3C:CF:2D:67:E4:F0:B0:4D:69:16:43:19:C1:6B:62:19:00:B6` |

### 发版 SOP

```bash
# 一条命令: 检查签名 → 打包 → 打印指纹
bash tools/build-apk.sh                          # 生产域名
bash tools/build-apk.sh http://192.168.1.200:3004  # 内测 (局域网)

# 装之前对一眼: 旧版 App → 我的 → 网络自检 → 「安装包」那行的签名前 16 位
#   必须与新 APK 的 SHA-256 前 16 位一致 (0DB0A1BCFF6DA703)
```

> ⚠️ keystore 丢了 = 以后所有版本的签名都变了 = **全体用户必须卸载重装**。请把
> `/home/tooyan/nuankebao-keys/` 备份到与代码异地的地方 (建议纳入 `deploy/backup.sh` 的加密备份清单)。
