# 暖客宝 运维 SOP (Standard Operating Procedure)

> 主人日常运维参考
> 配套 `docs/deploy.md` (一次性部署指南) 和 `tools/backup.sh` (自动化脚本)

## 📋 日常运维 (每 5 分钟看一次)

```bash
# 服务状态
cd /opt/nuankebao && docker compose ps

# 实时日志
docker compose logs -f --tail=100

# 健康检查
curl https://nuankebao.tooyang.top/api/health
```

## 🔔 告警阈值

| 指标 | 阈值 | 行动 |
|---|---|---|
| `/api/health` 返回 503 | 立即 | 看 web 日志 + db 日志 |
| Postgres 连接失败 | 立即 | `docker compose restart postgres` |
| 磁盘使用 > 80% | 24h 内 | 清理旧备份, 扩容 |
| 备份失败 | 立即 | 看 `/var/log/nuankebao-backup.log` |
| Nginx 502/504 | 立即 | 看 `journalctl -u nginx` |

## 🗓️ 每周任务

```bash
# 周一: 健康检查
cd /opt/nuankebao && ./tools/health-check.sh

# 周三: 备份文件检查
ls -lh /opt/nuankebao/backups/ | tail -5
# 确认最近 7 天每天有备份

# 周五: 磁盘检查
df -h | grep -E '(/$|/opt)'
du -sh /opt/nuankebao/backups/
```

## 🗓️ 每月任务

```bash
# 1. 异地同步检查
rclone ls remote:nuankebao-backups/ | wc -l
# 应 >= 30 (1 个月备份数)

# 2. 恢复演练 (重要! 至少每季度 1 次)
sudo ./tools/restore.sh /opt/nuankebao/backups/backup-$(date -d "2 weeks ago" +%Y%m%d)*.tar.gpg
# 验证后可以再恢复, 不影响线上

# 3. 更新系统
sudo apt update && sudo apt upgrade -y
# 暖客宝 暂不需要重启 (除非 Postgres 大版本更新)

# 4. 检查 Postgres 慢查询
docker exec nuankebao-postgres psql -U nuankebao -d nuankebao -c "
  SELECT query, calls, mean_exec_time
  FROM pg_stat_statements
  ORDER BY mean_exec_time DESC LIMIT 10;"
```

## 🗓️ 每季度任务

- [ ] **恢复演练** (1 次, 关键!)
- [ ] 密钥轮换评估
  - AUTH_SECRET (建议每 6 月轮换)
  - PGCRYPTO_KEY (建议每年轮换)
  - POSTGRES_PASSWORD (建议每年轮换)
- [ ] 数据库归档 + 索引重建
  ```bash
  docker exec nuankebao-postgres psql -U nuankebao -d nuankebao -c "VACUUM FULL;"
  docker exec nuankebao-postgres psql -U nuankebao -d nuankebao -c "REINDEX DATABASE nuankebao;"
  ```

## 🗓️ 每年任务

- [ ] 完整密钥轮换 (按 `docs/deploy.md` §7.3)
- [ ] 服务器续费 / 硬件检查
- [ ] SSL 证书自动续期验证 (`certbot renew --dry-run`)
- [ ] 备份策略评估 (容量 / 保留期)

## 🚨 故障排查手册

### 症状 1: 暖客宝 网页打不开

```bash
# Step 1: 看服务状态
cd /opt/nuankebao && docker compose ps
# nuankebao-web 是 Exit 1?

# Step 2: 看错误日志
docker compose logs web --tail=50

# Step 3: 常见原因 + 修复
# 原因 A: 数据库连接失败
docker compose restart postgres
sleep 10  # 等健康
docker compose restart web

# 原因 B: 端口冲突
ss -tlnp | grep 3003
./tools/check-port.sh 3003  # 确认空闲
# 如果占用, docker compose down + 改 .env APP_PORT

# 原因 C: 磁盘满
df -h
du -sh /opt/nuankebao/public/uploads/  # 照片占空间
# 清理旧照片: 找过大的, 备份后删除
```

### 症状 2: 暖客宝 登录后白屏

```bash
# Step 1: 看 Next.js 编译错误
docker compose logs web | grep -i error

# Step 2: 清缓存重建
docker compose down web
docker compose build web --no-cache
docker compose up -d web

# Step 3: 看 dev server (如果用 pnpm dev)
pkill -f "next dev"  # 杀掉所有 dev server
pnpm dev > /tmp/nuankebao-dev.log 2>&1 &
```

### 症状 3: 备份失败

```bash
# Step 1: 看日志
cat /var/log/nuankebao-backup.log | tail -30

# Step 2: 常见原因
# 原因 A: BACKUP_PASSPHRASE 未设
grep BACKUP_PASSPHRASE /opt/nuankebao/.env

# 原因 B: Postgres 连接失败
docker exec nuankebao-postgres pg_isready -U nuankebao
# 应返回 "accepting connections"

# 原因 C: 磁盘满
df -h | grep /opt

# 原因 D: GPG 损坏
gpg --version  # 验证 gpg 可用
echo "test" | gpg --symmetric --passphrase test  # 测试
```

### 症状 4: 性能下降

```bash
# Step 1: 找慢查询
docker exec nuankebao-postgres psql -U nuankebao -d nuankebao -c "
  SELECT pid, query, state, query_start, now() - query_start AS duration
  FROM pg_stat_activity
  WHERE state != 'idle' AND now() - query_start > interval '5 seconds'
  ORDER BY duration DESC;"

# Step 2: 强制 vacuum
docker exec nuankebao-postgres psql -U nuankebao -d nuankebao -c "VACUUM ANALYZE;"

# Step 3: 看磁盘 IO
iostat -x 1 5
# 如果 %util 接近 100%, 考虑加 SSD

# Step 4: 加索引 (看 query plan)
docker exec nuankebao-postgres psql -U nuankebao -d nuankebao -c "EXPLAIN ANALYZE SELECT * FROM wellness_record WHERE customer_id = 1;"
# 如果 Seq Scan, 加 customer_id 索引 (已经存在)
```

### 症状 5: 飞书 / 邮件告警集成

如需在异常时通知主人, 有 3 个方案:

#### 方案 A: 飞书机器人 (推荐, 免费)

```bash
# 1. 飞书群 → 设置 → 群机器人 → 添加 webhook
# 2. 保存 URL: https://open.feishu.cn/open-apis/bot/v2/hook/xxxxx
# 3. 写脚本 /opt/nuankebao/tools/notify-feishu.sh:
cat > /opt/nuankebao/tools/notify-feishu.sh << 'EOF'
#!/bin/bash
WEBHOOK="你的飞书webhook"
MESSAGE="$1"
curl -X POST "$WEBHOOK" \
  -H "Content-Type: application/json" \
  -d "{\"msg_type\":\"text\",\"content\":{\"text\":\"$MESSAGE\"}}"
EOF
chmod +x /opt/nuankebao/tools/notify-feishu.sh

# 4. 在 health-check.sh 加:
# if [ -z "$HEALTH" ]; then
#   /opt/nuankebao/tools/notify-feishu.sh "暖客宝 健康检查失败!"
# fi
```

#### 方案 B: 邮件 (SendGrid / 阿里云邮件推送)

```bash
sudo apt install -y msmtp
# 配置 ~/.msmtprc (略)
```

#### 方案 C: Telegram Bot

```bash
# 创建 bot 拿 token
# 写脚本 curl Telegram API
```

## 🆘 紧急联系人

- 主人: <你的手机>
- 阿里云工单: https://workorder.console.aliyun.com
- Let's Encrypt 社区: https://community.letsencrypt.org

## 📚 参考文档

- `docs/deploy.md` — 完整部署指南
- `docs/security-compliance.md` — 安全合规
- `docs/data-model.md` — 数据模型
- `docs/phase-1-mvp.md` — 实施计划
- `docs/w1-implementation.md` — W1 实施日志
- `docs/w4-implementation.md` — W4 实施日志 (Phase 1.5 备份恢复)
- `tools/backup.sh` — 自动化备份
- `tools/restore.sh` — 恢复脚本
- `tools/check-port.sh` — 端口检测
- `tools/pre-commit-port-check.sh` — 提交前端口校验

## ✅ 部署后勾选

- [ ] 主机名记入 `/etc/hostname` 备注
- [ ] 服务器 IP 记入 SOP
- [ ] 域名解析到正确 IP
- [ ] 备份密码 (暖客宝 主人) 记入密码管理器
- [ ] SSH 密钥备份到 U 盘 (异地)
- [ ] 飞书 / 邮件告警集成
- [ ] 第一次恢复演练通过
- [ ] 1-2 销售内测 1 周, 收集反馈