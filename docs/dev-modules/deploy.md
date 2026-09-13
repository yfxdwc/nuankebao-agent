# deploy — 部署脚本模块

> **职责**: 项目级部署 + 备份 + 监控脚本 (主人自有物理服务器)
> **物理位置**: `tools/` + `deploy/` + systemd units (`deploy/systemd/`)
> **入口**: `bash deploy/install-systemd.sh` 一键装 systemd user timers + enable

## 当前实现

### `deploy/` (项目级备份栈, 2026-09-08 拍板)

| 文件 | 职责 |
|---|---|
| `deploy/backup.sh` | PG (pg_dump -Fc) + Media (tar --zstd) → GPG AES256 加密 → 本地 + 异地 rsync → GFS 双保险 (mtime+14 AND count≤7) |
| `deploy/code_snapshot.sh` | dirty + untracked + .git/ → 外置盘异地 (zstd level 19), 含 sha256 + manifest sidecar, fail-closed 预检 secret basename |
| `deploy/restore_verify.sh` | 月度演练: 解密 → 起临时 PG:5435 → pg_restore → 14 张关键表行数比对 (生产 vs 演练) → 自动清理 |
| `deploy/install-systemd.sh` | 一键装 6 个 systemd user unit (3 service + 3 timer) + enable --now |
| `deploy/README.md` | §10 备份 SOP 落地文档 (架构 / 调度 / 安装 / 安全 / 排错 / 验收) |
| `deploy/systemd/` | 6 个 unit |

### `deploy/systemd/` (6 个 unit, 3 对 service+timer)

| Service + Timer | 调度 | 职责 |
|---|---|---|
| `nuankebao-backup.{service,timer}` | 日 03:00 | PG + Media 备份 |
| `nuankebao-code-snapshot.{service,timer}` | 日 04:00 | 代码快照 (错开 backup 1h) |
| `nuankebao-restore-verify.{service,timer}` | 月第一周日 04:00 | 备份演练 |

每个 timer: `Persistent=true` (错过则下次启动补跑) + `RandomizedDelaySec=5min` (防多机同时跑).

### `tools/` (部署工具脚本)

| 文件 | 职责 |
|---|---|
| `tools/check-env.sh` | 工具链自检 (docker / pnpm / node / git) |
| `tools/check-port.sh` | 端口检测 (避免撞主人其他项目, per AGENTS §6.1) |
| `tools/pre-commit-port-check.sh` | git commit 时端口硬约束 (per AGENTS §3) |
| `tools/check-migration-compat.sh` | DB migration 向后兼容检查 (per CHARTER §3.5) |
| `tools/build-flutter-web.sh` | Flutter web 一键 build + sync (per dev-modules/flutter-preview/) |
| `tools/nuankebao-*.sh` | 部署 / tunnel / stack 启停 |

### Deprecated / Redirect

- `tools/backup.sh` → `exec deploy/backup.sh "$@"` (透明跳转)
- `tools/restore.sh` → `exit 1` (覆盖式恢复危险, 改走演练 + 手动)
- `tools/backup-cron.sh` → `exit 1` (cron 改 systemd timer)

### 数据目录 (`/home/tooyan/nuankebao-databackups/`)

⚠ gitignored, 项目外独立备份目录 (防 rm -rf):
- `backup-key.gpg` (chmod 600, GPG passphrase-file)
- `pg-backups/` (GFS 7 份)
- `media/` (GFS 7 份)
- `backup-health/` (atomic JSON 状态)
- `logs/` (chmod 700 dir, 持久化日志)

异地副本: `/media/tooyan/<盘符>/nuankebao-*` (3-2-1 异地策略).

## 扩展指南

**新增定时任务** (e.g. 周报聚合):
1. 在 `deploy/systemd/` 加 `<name>.{service,timer}` 2 个文件
2. 跑 `bash deploy/install-systemd.sh` 重装
3. deploy/README.md 更新

**切换异地盘** (新外置盘挂载):
1. 改 `deploy/backup.sh` 里的 `REMOTE_DEST` 路径
2. ⚠ smoke test 验证 rsync 能写
3. 旧异地盘保留 1 周观察期再卸

**升级备份策略** (e.g. 加 S3 异地):
1. 加新异地 destination (S3 bucket)
2. backup.sh 加 s3 sync 步骤
3. restore_verify.sh 加 S3 拉取步骤
4. ⚠ 主人 review (云上密钥管理)

## 3-2-1 副本策略 (per SOP §2.1)

- 本地 (nvme) + 异地 (外置盘 /media/tooyan) + systemd timer 调度
- GPG 对称 AES256 加密 + passphrase-file
- GFS 双保险 mtime+14 AND count≤7
- fail-closed 预检 secret basename 黑名单 + 应排除路径检查

## 密钥管理

⚠ **生产密钥主人请备份到密码管理器**:
- 主密钥: `/home/tooyan/nuankebao-databackups/backup-key.gpg` (chmod 600)
- 异地副本: `/media/tooyan/<盘符>/nuankebao-databackups/.backup-key/backup-key.gpg`

## 相关 SOP

- [deploy/README.md §10 备份 SOP 落地文档](../../deploy/README.md)
- [docs/CHARTER.md §3.3 部署红线 (Docker Compose / 强密码 / 每日备份 / 不存生产凭证)](../../CHARTER.md)
- [PHYSICAL_OPS.md](../../PHYSICAL_OPS.md) (主人机器物理操作 SOP)
- AGENTS.md §6.1 异地盘副本路径

## 待办

- [ ] GitHub 镜像 + monitor (主人 2026-09-08 拍板 skip, 暂不需要)
- [ ] Cloudflare Tunnel 自动重连 (当前依赖 systemd 重启)
- [ ] restore_verify 加跨盘对比 (本地 vs 异地)
- [ ] 备份 dashboard (主人 review 用)
