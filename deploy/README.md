# 暖客宝 部署与运维 SOP

> 本目录是项目级运维脚本 + systemd units + 备份 SOP 落地处。
>
> **当前活跃脚本**:
> - `backup.sh` — 工业级备份 (PG + Media + GPG + 异地 + GFS) — dev-domain-backup SOP §3.1
> - `code_snapshot.sh` — 代码快照 (dirty + untracked → 外置盘) — §3.2
> - `restore_verify.sh` — PG 月度演练 (decrypt → temp PG → 行数比对) — §3.4
> - `install-systemd.sh` — 一键装 systemd user timers + enable
> - `systemd/*.service + *.timer` — 6 个 unit (3 对)
>
> **不装**: GitHub 镜像 + monitor (主人 2026-09-08 拍板 skip, 项目无 remote)

---

## §10. 备份运维 (dev-domain-backup SOP)

> **设计源**: `~/.muse/skills/dev-domain-backup/SKILL.md` (v1.0, 2026-09-07 canonical)
>
> **取代**: 项目根 `tools/backup.sh` + `tools/restore.sh` + `tools/backup-cron.sh` (cron 版) — 已 deprecated, 保留供历史.

### §10.1 备份架构总览 (3-2-1)

```
              ┌──────────────────────────────────────────────┐
              │      暖客宝 备份 (3-2-1 + GFS + GPG)          │
              └──────────────────────────────────────────────┘
                                │
              ┌─────────────────┼──────────────────┐
              ▼                 ▼                  ▼
   ┌────────────────────┐ ┌──────────────┐ ┌────────────────────────┐
   │ 本地副本 (1)        │ │ 异地盘 (2)   │ │ systemd timer (3) 调度  │
   │ nuankebao-databack │ │ /media/tooyan/<盘符>/  │ │ - backup.timer  03:00   │
   │   ups/pg-backups/  │ │   <盘符>/   │ │ - code-snapshot 04:00   │
   │   ups/media/       │ │   nuankebao- │ │ - restore-verify        │
   │                    │ │   databackups│ │   月第一周日 04:00       │
   │ (chmod 700)        │ │              │ │                        │
   └────────────────────┘ └──────────────┘ └────────────────────────┘
            │                    │
            ▼                    ▼
   ┌──────────────────────────────────────────────────┐
   │  GPG 对称加密 (AES256 + passphrase-file)         │
   │  密钥: backup-key.gpg (chmod 600, 异地副本同权限) │
   │  明文落盘后立即 shred -u (不残留)                  │
   └──────────────────────────────────────────────────┘
```

### §10.2 数据源 + 备份命令

| 数据 | 命令 | 频率 | 异地策略 |
|---|---|---|---|
| PostgreSQL | `pg_dump -Fc` + GPG | 日 03:00 | rsync --delete-after |
| Media (public/uploads) | `tar --zstd` + GPG | 日 03:00 | rsync --delete-after |
| 源码 (committed + dirty + untracked) | `tar --zstd` (含 .git/) | 日 04:00 | 直接写异地盘 |

**关键实现细节**:
- **PG 必须 `-Fc`** 自定义压缩 (非 plain text, 巨大且不可 `pg_restore`)
- **Media 必须排除 `.gitkeep` + `cache` + `purged`** (空目录标记 / preview 衍生品 / 已逻辑删除)
- **Code snapshot 必含 `.git/`** (异地能还原 commit 历史)
- **Code snapshot fail-closed 预检** (SOP §2.5) — 命中 secret basename 或漏排除 → exit 4 + alert

### §10.3 目录布局

```
/home/tooyan/nuankebao-agent/
├── deploy/                                    ← 本目录 (备份运维)
│   ├── backup.sh                              ← 工业级备份 (§10.1)
│   ├── code_snapshot.sh                       ← 代码快照 (§10.2)
│   ├── restore_verify.sh                      ← PG 月度演练 (§10.5)
│   ├── install-systemd.sh                     ← 一键装 systemd timers
│   ├── README.md                              ← 本文件
│   └── systemd/
│       ├── nuankebao-backup.{service,timer}
│       ├── nuankebao-code-snapshot.{service,timer}
│       └── nuankebao-restore-verify.{service,timer}
├── data/                                      ← ⚠ gitignored (chmod 700 健康 state + 备份日志)
│   ├── backup-key.gpg                         ← GPG 密钥 (chmod 600)
│   ├── backup-health/                         ← atomic JSON 状态
│   │   ├── backup.json
│   │   ├── code-snapshot.json
│   │   └── restore-verify.json
│   ├── logs/
│   │   ├── backup.log
│   │   ├── code-snapshot.log
│   │   └── restore-verify.log
│   └── .gitignore                             ← gitignore 自己 + 内部一切

/home/tooyan/nuankebao-databackups/               ← ⚠ gitignored (项目外独立备份目录, 防 rm -rf 误删)
├── backup-key.gpg                             ← GPG 密钥 (chmod 600, 主副本)
├── pg-backups/
│   └── pg-YYYYMMDD-HHMMSS.dump.gpg            ← GFS 保留 7 份 (mtime+14)
├── media/
│   └── media-YYYYMMDD-HHMMSS.tar.zst.enc      ← GFS 保留 7 份
├── backup-health/                             ← atomic JSON (同 agent/data/backup-health)
└── logs/

/media/tooyan/<盘符>/<盘符>/nuankebao-databackups/      ← 异地盘副本
├── .backup-key/                               ← 隐藏目录 + 700 (异地密钥副本)
│   └── backup-key.gpg                         ← chmod 600
├── pg-backups/                                ← rsync --delete-after 同步本地
└── media/                                     ← rsync --delete-after 同步本地

/media/tooyan/<盘符>/<盘符>/nuankebao-codebackups/      ← 异地盘代码快照 (独立 dir, 不走 rsync)
├── nuankebao-agent-YYYYMMDD-HHMMSS.tar.zst
├── .sha256 / .manifest.json / .manifest.txt
└── (GFS 保留 7 份)
```

### §10.4 GFS 双保险 + 调度

**保留策略** (SOP §2.4):
- **mtime +14 天** 删除 (粗粒度)
- **count ≤ 7** 保底份数 (count 超 7 时按 mtime 升序删最旧 excess 个)
- **两条件并集**: 任一命中即删

**调度** (systemd timer, Persistent=true + RandomizedDelaySec):

| Timer | OnCalendar | 错峰理由 |
|---|---|---|
| `nuankebao-backup.timer` | `*-*-* 03:00:00` | 凌晨低负载, 03:00 抢首 |
| `nuankebao-code-snapshot.timer` | `*-*-* 04:00:00` | 错开 backup 1h, 防 rsync 重叠 |
| `nuankebao-restore-verify.timer` | `Sun *-*-1..7 04:00:00` | 月度演练, 不与日常冲突 |

**`RandomizedDelaySec=5min`**: 防集群同时跑 / 雪崩.

### §10.5 PG 月度恢复演练

**目标**: 每月验证"备份可解 + 数据完整 + 异构恢复链路通"

**流程** (§3.4):
1. 找最近一份 PG 加密备份 (`ls -1t pg-*.dump.gpg | head -1`)
2. GPG 解密 → `/tmp/pg-verify/verify.dump`
3. `pg_restore --list` 验证 dump 格式完整
4. 起临时 PG 容器 `nuankebao-pg-verify:5435` (与生产端口 5432 隔离)
5. `pg_restore` 到临时容器
6. **14 张关键表行数比对** (生产 vs 演练) — 100% 一致 = 成功
7. 自动清理临时容器 + staging
8. 失败 → 写 health state + 飞书红卡 (待主人配置)

**关键表** (14 张, 含 `audit_log` dual-write):
```
customer / wellness_record / wellness_record_body_part
wellness_record_product / follow_up_task / interaction
product / service_item / body_part / store / staff / user
wellness_knowledge / audit_log
```

**实测**: 2026-09-08 dry-run 验证脚本通过 (`bash -n` + 全路径解析), 首次真实演练等下一次月度触发 (2026-10-04 周日 04:00).

### §10.6 安装与运维

#### 10.6.1 一键安装

```bash
cd /home/tooyan/nuankebao-agent
./deploy/install-systemd.sh
```

效果: 6 个 unit 复制到 `~/.config/systemd/user/` + `daemon-reload` + 3 个 timer `enable --now`.

#### 10.6.2 手动触发

```bash
# 立即跑一次 backup
systemctl --user start nuankebao-backup.service

# 立即跑一次 code snapshot
systemctl --user start nuankebao-code-snapshot.service

# 立即跑一次月度演练 (强制)
systemctl --user start nuankebao-restore-verify.service
```

#### 10.6.3 看日志

```bash
# systemd journal (主通道, 含所有 stderr/stdout)
journalctl --user -u nuankebao-backup -f

# 持久化日志 (chmod 700 dir, 700 文件)
tail -f /home/tooyan/nuankebao-databackups/logs/backup.log
tail -f /home/tooyan/nuankebao-databackups/logs/code-snapshot.log
tail -f /home/tooyan/nuankebao-databackups/logs/restore-verify.log
```

#### 10.6.4 看健康状态

```bash
# JSON 状态 (atomic write, chmod 600)
cat /home/tooyan/nuankebao-databackups/backup-health/backup.json | jq
cat /home/tooyan/nuankebao-databackups/backup-health/code-snapshot.json | jq
cat /home/tooyan/nuankebao-databackups/backup-health/restore-verify.json | jq
```

### §10.7 安全 (GPG + chmod + gitignore)

| 资产 | 路径 | 权限 | 备注 |
|---|---|---|---|
| GPG 密钥 | `/home/tooyan/nuankebao-databackups/backup-key.gpg` | 600 | 主副本 |
| GPG 密钥 (异地) | `/media/tooyan/<盘符>/<盘符>/nuankebao-databackups/.backup-key/backup-key.gpg` | 600 | 隐藏目录 700 |
| 健康 state | `*/backup-health/*.json` | 600 | atomic write |
| 备份副本 | `*/pg-backups/` + `*/media/` | 600 | rsync 收紧 |
| 代码快照 | `/media/tooyan/<盘符>/<盘符>/nuankebao-codebackups/` | 600 | 含 .git/ |
| 备份日志 | `/home/tooyan/nuankebao-databackups/logs/` | 700 dir | 由 systemd append 写 |

**密钥管理红线** (SOP §2.2):
- ❌ **口令本身不入文件**: 用 passphrase-file 模式, GPG 读文件自动解密
- ❌ **密钥不入仓库**: `data/` + `/home/tooyan/nuankebao-databackups/` 都在 `.gitignore`
- ✅ **密钥异地副本**: 防本机 nvme 故障 → 外置盘可解密外置盘的加密备份 (逻辑闭环)

**密钥轮换**: 主人需轮换时 (`ASK_USER` 拍板):
1. 新密钥生成: `openssl rand -base64 32 > backup-key.gpg.new && chmod 600`
2. 双密钥并行 (老密钥解密历史备份, 新密钥加密新备份)
3. 待所有历史备份自然过期 (GFS 14 天 + 7 份) → 删老密钥

### §10.8 排错 SOP

| 症状 | 根因 | 修复 |
|---|---|---|
| `tar: Permission denied` | systemd `ReadWritePaths` 没含数据目录 | 检查 unit `ReadWritePaths=...` |
| `pg_dump: connection failed` | docker container 没起 | `systemctl start nuankebao-stack.service` |
| `GPG: passphrase failed` | 密钥文件被改 / 权限错 | `chmod 600 backup-key.gpg` + `gpg --passphrase-file` 测试 |
| `rsync: command not found` | systemd `PATH` 不含 `/usr/bin` | unit 加 `Environment="PATH=/usr/local/bin:/usr/bin:/bin"` |
| `外置盘未挂载` | mountpoint -q 失败 | 自动 WARN (不 exit 错), RPO 退化为本地单副本 |
| `restore-verify: 0 rows` | 备份本身坏 / 密钥错 | `gpg -d` 测试 + `pg_restore --list` 看内容 |
| `code snapshot 预检 exit 4` | 命中 secret basename | 检查仓库内是否有 `.env` / `.pem` / `token` 等 — 应在 `.gitignore` |
| `flock: 资源暂时不可用` | 上一轮未跑完 | `cat /home/tooyan/nuankebao-databackups/backup-health/.backup.lock` 看 PID |

### §10.9 验收清单 (新建 / 改 / 排错后)

- [x] GPG 密钥文件 `chmod 600` + 入 `.gitignore` (主 + 异地副本)
- [x] systemd timer `enable --now` + `list-timers` 验证 (**Persistent=true**)
- [x] 手动跑一次 `deploy/backup.sh` 看 `exit code` (必须非 0 if 任何步骤失败)
- [x] 异地 rsync 验证 (`mountpoint -q` + `ls` 异地副本)
- [ ] 月度演练跑通 (PG 行数 100% 一致) — 等 2026-10-04 首次真实触发
- [x] health state 写盘 (atomic JSON, 0600 文件 / 0700 dir)
- [x] 排除列表预检 (含 secret basename + 应排除路径检查)
- [x] GFS 清理日志 (`mtime+14 AND count<=7` 双保险命中数)
- [x] `loginctl enable-linger mm7` 已开 (systemd user 持久化)
- [x] `RandomizedDelaySec` ≥ 5min (防雪崩)

### §10.10 与本机其它 skill 的边界

| Skill | 关系 | 备注 |
|---|---|---|
| `dev-domain-backup` (本 SOP 源) | **canonical** | 实施依据 |
| `sysops` | **不冲突** | 主机级 vs 本 skill 项目级 |
| `cron-scheduler` | **不冲突** | 备份调度用 systemd, 不混 cron |
| `scaffold-task-snapshot` | **不冲突** | 开发期 git tag vs 备份级 tar |
| `backup` (mm7 L2) | **不冲突** | 个人 home 级 vs 项目级 |

### §10.11 历史 (已 deprecated, 保留供考古)

- `tools/backup.sh` — v1 cron 包装版 (BBT_DIR=/opt/nuankebao, BACKUP_PASSPHRASE env). 已 deprecated. 见 `tools/CHANGELOG-DEPRECATED.md` (待补).
- `tools/restore.sh` — v1 灾难恢复脚本 (覆盖式). 已 deprecated. 演练改走 `deploy/restore_verify.sh` (隔离演练, 不覆盖生产).
- `tools/backup-cron.sh` — crontab 包装. 已 deprecated. 调度改走 systemd timer.

---

## 附录 A: 设计原则 (dev-domain-backup §2)

1. **3-2-1 副本** — 至少 3 份 + 2 介质 + 1 离机
2. **全部加密** — GPG 对称 AES256 + passphrase-file
3. **调度用 systemd** — 不混 cron (Persistent + RandomizedDelay)
4. **GFS 双保险** — mtime+14 AND count≤7 并集
5. **fail-closed 预检** — secret 黑名单 + 应排除路径检查

## 附录 B: 11 条硬约束 (SOP §4)

1. ❌ 备份明文落盘 (必须 GPG)
2. ❌ 口令本身入文件 (必须 passphrase-file)
3. ❌ cron 代替 systemd timer
4. ❌ 只 mtime 或只 count 清理 (双保险)
5. ❌ rsync 不带 `--delete-after`
6. ❌ 备份脚本 silent failure
7. ❌ 代码快照含 secret / data / deps
8. (skip — GitHub 镜像未启用)
9. (skip — GitHub 镜像未启用)
10. ❌ 远端卷校验跳过
11. ❌ 多 cron 同时跑同一脚本 (flock 防)
