# BBT-Agent → 暖客宝-Agent 全套改名 SOP

> **状态**: 阶段 1-2 完成 (2026-09-06 18:24), 阶段 3-8 待主人手工跑脚本
> **拍板日**: 2026-09-06
> **方案**: full-internal + pg-dump-restore + rename-dir(主人 3/3 全选)
> **已完成**:
> - 阶段 1 锁仓 + 备份 (crontab / pg_dump / git baseline `0233f3f`)
> - 阶段 2 mv 目录 + kill PID 132018
> **下一步**: 主人跑 `bash tools/nuankebao-rename-execute.sh all`
> **预期断服剩余**: 30-90 秒

---

## 0. 当前快照(执行前 baseline)

| 项目 | 状态 |
|---|---|
| `nuankebao-postgres` 容器 | Up 6 hours, healthy |
| `nuankebao-web` 容器 | **不存在**(`docker compose up` 失败,既有 bug,与改名无关) |
| `nuankebao-postgres-data` volume | 存在,named volume |
| `bbt-stack.service` (system) | activating auto-restart (`nuankebao-web` 起不来,死循环) |
| `bbt-nextjs.service` (user) | **不在 /etc/systemd/system/**,在 `~/.config/systemd/user/` — 当前未 active |
| `bbt-cloudflared.service` (system) | active running, 但用 `--url http://localhost:3003` 临时隧道(PID 4303) |
| mm7 命名隧道 `a8957e6c...` | PID 2222 active,响应 `~/.cloudflared/config.yml` 所有 ingress |
| **`next dev -p 3003` 孤儿进程** | **PID 132018 active**,从 `tools/start-dev.sh` 启动(13:53),cwd=`/home/mm7/nuankebao-agent`,PPID 1942 (systemd user)。**响应公网所有请求 — 改名期间不能 kill** |
| `nuankebao.tooyang.top` DNS | **已通**(307,Next.js 正常响应 /admin) |
| `bbt.tooyang.top` DNS | **已通**(307,主人拍「立即删」) |
| Postgres `bbt` 库 | 11 张表 + audit_log,**无业务数据**(W1 schema only) |
| Postgres `bbt_test` 库 | 测试库(可丢) |
| `.env` POSTGRES_USER/DB | `bbt`(未迁移) |
| `.env` AUTH_URL | `https://nuankebao.tooyang.top`(已切) |
| git status | 20+ 文件 modified,未提交 |
| git remote | 无(纯本地) |
| crontab (mm7 user) | `post-boot-check.sh` + `adb-watchdog.sh`,都引用 `/home/mm7/nuankebao-agent/` |
| 3003 端口 | PID 132018 next-server 在响应 |
| 3000/3010 端口 | 其他项目(非本仓库)|

---

## 1. Gate 0: 主人必须确认的 4 件事

### G0-1 ⚠ Cloudflare Dashboard DNS
主人到 Cloudflare Dashboard → DNS → Records:
- **`bbt.tooyang.top`** CNAME 指向 `a8957e6c-6417-4468-a8d6-c8ed1aa5106f.cfargotunnel.com` ✅
- **`nuankebao.tooyang.top`** CNAME 指向 `a8957e6c-6417-4468-a8d6-c8ed1aa5106f.cfargotunnel.com` ✅

**agent 验证**: `getent hosts` 两条都解析到 `2606:4700:3031::6815:3f67` + `2606:4700:3036::ac43:aa8d` (Cloudflare CDN) ✅ ✅
**下一步**: 阶段 8 主人手工删 `bbt.tooyang.top` DNS 记录(主人拍「立即删」)。

### G0-2 ⚠ Cloudflare Tunnel Public Hostname
主人到 Cloudflare Dashboard → Zero Trust → Networks → Tunnels → 选 `a8957e6c-...` → Public Hostnames:
- `bbt.tooyang.top` → `http://localhost:3003` (需删)
- `nuankebao.tooyang.top` → `http://localhost:3003` (✅ 已在 `~/.cloudflared/config.yml` 配)

**agent 验证**: `~/.cloudflared/config.yml` 第 4 段含 `nuankebao.tooyang.top` ingress ✅
**下一步**: 阶段 8 主人手工删 `bbt.tooyang.top` Public Hostname 记录。

### G0-3 ⚠ `bbt-stack.service` failed 的根因
docker logs 显示 `nuankebao-postgres` 跑得很正常,`nuankebao-web` 根本没起过。可能原因:
- `nuankebao-web` build 失败
- 端口冲突(next dev systemd 已占 3003, compose 起 web 也想绑 3003)
- `AUTH_SECRET` 缺失(现在 .env 已加)

**取舍**: 本 SOP 阶段 3 顺手解决(`bbt-stack.service` 改成只管 postgres, web 走 systemd next dev,因为 next dev 才是调试模式)。

### G0-4 ⚠ 时机
外部服务会断 30-60 分钟。**主人确认当前没有销售员在用 APK,没有 admin 在调试**。

---

## 2. 8 阶段执行计划

### 阶段 1: 锁仓 + 备份(15 分钟)
**目的**: 万一出错能回滚

**重要原则: 阶段 1 只锁仓 + 备份, 不动运行服务**

| 步骤 | 命令 | Gate |
|---|---|---|
| 1.1 备份 crontab | `crontab -l > /tmp/crontab.bak && cat /tmp/crontab.bak` | 主人看内容 |
| 1.2 暂停 crontab | `crontab -r` | |
| 1.3 DB dump | `docker exec nuankebao-postgres pg_dump -U bbt -d bbt --format=custom --no-owner -Fc > /tmp/bbt-pre-rename.dump` | |
| 1.4 验证 dump | `pg_restore -l /tmp/bbt-pre-rename.dump \| head -20` | 必须看到 11 张表 |
| 1.5 git commit baseline | `git add -A && git commit -m "chore(rename): baseline before full rename bbt-agent → nuankebao-agent"` | 主人拍 |

**⚠ 阶段 1 不停任何服务**:
- `bbt-stack.service` activating auto-restart 一直跑 (nuankebao-postgres 在响应 docker compose up)
- PID 132018 (next dev) 不能 kill
- mm7 命名隧道 PID 2222 不能 kill
- 临时隧道 PID 4303 留着(阶段 7 才停)

**回滚点**: 1.1-1.4 任意失败 → `crontab /tmp/crontab.bak` 即可,不影响服务。

---

### 阶段 2: 仓库物理改名(5 分钟)
**目的**: `bbt-agent` 目录 → `nuankebao-agent`

| 步骤 | 命令 | 风险 |
|---|---|---|
| 2.1 | `cd /home/mm7 && mv bbt-agent nuankebao-agent` | 低(mv 是原子操作) |
| 2.2 | 验证: `ls /home/mm7/nuankebao-agent/AGENTS.md` | |
| 2.3 | 验证 git: `git -C /home/mm7/nuankebao-agent status -s` | 应见到 0 行 modified(baseline 已 commit) |
| 2.4 | **重拉 PID 132018 的 next dev**(cwd 断了) | **中-高**: mv 后 PID 132018 的 cwd 指向旧路径 → 虽不崩但内部逻辑会出问题,可能要 kill 重拉 |

**⚠ PID 132018 处理**:
mv 之后 PID 132018 的 cwd 会指向不存在的 `/home/mm7/nuankebao-agent` (文件系统变了)。next dev 通常 cwd 只用于相对路径,如果它用 cwd 访问文件,可能报错。建议:
- 选项 A: 阶段 2.4 直接 `kill 132018`,启动新的 next dev 在新目录(主人接受 5-10 分钟断服)
- 选项 B: 保持 PID 132018 不动,等所有改名完成,在阶段 7 kill + 重拉(总断服时间 < 1 分钟)

**推荐选项 B**: 减少断服时间。

**回滚**: `mv nuankebao-agent bbt-agent` (1 行命令, 完整回滚)

---

### 阶段 3: systemd service + tunnel 改名(20 分钟)
**目的**: 所有 systemd 单元指向新目录 + 命名隧道接管

| 步骤 | 文件改动 | 风险 |
|---|---|---|
| 3.1 | `tools/bbt-stack.service` → `tools/nuankebao-stack.service`,改 `WorkingDirectory=/home/mm7/nuankebao-agent` | 低(文本) |
| 3.2 | `tools/systemd/bbt-nextjs.service` → `tools/systemd/nuankebao-nextjs.service`,改 `WorkingDirectory` + `EnvironmentFile` + `ExecStart` 路径 | 低(文本) |
| 3.3 | `tools/install-systemd.sh` 同步改名 + 更新复制逻辑 | 低 |
| 3.4 | `sudo cp tools/nuankebao-*.service /etc/systemd/system/` | **需 sudo**(AGENTS §3 拍主人拍,这里是主人已拍 scope 内的合理 sudo) |
| 3.5 | `sudo systemctl daemon-reload` | 低 |
| 3.6 | `sudo systemctl disable bbt-stack.service`(让它不再 auto-restart) | **⚠ 中**: disable 后 docker compose 不再被 unit 拉起,但 PID 132018 + DB 还在跑 → 服务不中断 |
| 3.7 | 装新的 `nuankebao-stack.service` (**改为只跑 postgres** 不起 web,因为 next dev 是手拉的不冲突) | **修既有 bug** |
| 3.8 | `sudo systemctl enable nuankebao-stack.service && sudo systemctl start nuankebao-stack.service` | |
| 3.9 | **临时不动 `bbt-cloudflared.service`**(避免断公网); 在阶段 7 末尾再切到命名模式 | **⚠ 改名不立刻生效**, 阶段 7 才完整切 |

**为什么不立刻切到命名隧道**:
- mm7 命名隧道 PID 2222 已在跑,响应 nuankebao.tooyang.top ✓
- 临时隧道 PID 4303 也在跑
- 同时切可能产生流量真空(临时隧道退场,新命名 unit 还没起来)
- 保留临时隧道作为灰度兜底, 阶段 7 验证一切正常后才删

**nuankebao-stack service 调整**: 只跑 postgres,不起 web,ExecStart 改为 `docker compose up -d postgres`(target 而非全 stack)。这样不会跟手拉的 next dev 抢 3003 端口。

---

### 阶段 4: 内部代码替换(60 分钟)
**目的**: 代码层所有 `bbt` / `BBT` / `Bbt` 字符串替换

**机械替换**(rg + sed):
- `pubspec.yaml` `bbt_agent` → `nuankebao` + description
- 所有 `tools/bbt-*.sh` → `tools/nuankebao-*.sh`(mv + 内部路径)
- 脚本内部 `BBT_DIR` 默认值 `/opt/nuankebao` → `/opt/nuankebao`, `/home/mm7/nuankebao-agent` → `/home/mm7/nuankebao-agent`
- `tools/*.sh` 里所有 `nuankebao-postgres` container 名 → `nuankebao-postgres`
- `tools/*.sh` 里所有 `nuankebao-web` container 名 → `nuankebao-web`
- `tools/*.sh` 里所有 `nuankebao-nextjs.log` → `nuankebao-nextjs.log`
- `tools/*.sh` 里所有 `nuankebao-boot-check.log` → `nuankebao-boot-check.log`
- `tools/*.sh` 里所有 `nuankebao-backup.log` → `nuankebao-backup.log`
- `docker-compose.yml` 注释里的"保留 nuankebao-postgres 是代号" → 改成"内部代号,见 §6.3"
- `~/.cloudflared-bbt` → `~/.cloudflared-nuankebao`(云上备份目录,主人云上有才改)
- 所有 `docs/*.md` 叙述里的 BBT → 暖客宝 / NuankeBao

**保留**(§6.3 主人 9-05 拍板,**绝对不动**):
- 脚本内部环境变量 `BBT_DIR` / `BBT_PORT` / `BBT_HOSTNAME` 名称(只是值改路径,变量名不动 — 内部代号原则)
- `tools/SOP.md` 注释里说明 `bbt-*` 是历史命名(改为说明 `nuankebao-*` 是新命名)

**Flutter 端**(`flutter_app/`):
- `pubspec.yaml` `name: bbt_agent` → `name: nuankebao`
- Android package `cn.nuankebao.app` 已切,不动
- Dart class `BbtApp` → `NuankeBaoApp`(`grep -rn 'BbtApp\|BbtAgent' flutter_app/lib/`)
- dart-define 变量已切到 `NUANKEBAO_API_BASE`,不动

**GitHub Actions**(`tools/.github/`):
- 全部 `bbt` 字串替换

---

### 阶段 5: Postgres 迁移(15 分钟)
**目的**: `bbt` user/db → `nuankebao` user/db(用 pg_dump + restore,W1 阶段无业务数据安全)

| 步骤 | 命令 |
|---|---|
| 5.1 | 停 nuankebao-postgres:`docker compose stop postgres` |
| 5.2 | 删旧 volume:`docker volume rm nuankebao-postgres-data`(风险!主人拍) |
| 5.3 | 改 `docker-compose.yml` `container_name: nuankebao-postgres` → `nuankebao-postgres`,`name: nuankebao-postgres-data` → `nuankebao-postgres-data`(§6.3 说内部代号保留 — **这里有冲突**: 主人 9-05 拍保留,但 stage 5 改成 nuankebao 更一致。**需主人重新拍**) |
| 5.4 | 改 `.env` `POSTGRES_USER=bbt` → `nuankebao`,`POSTGRES_DB=bbt` → `nuankebao`,`POSTGRES_PASSWORD` 改新值 |
| 5.5 | 重建容器:`docker compose up -d postgres` |
| 5.6 | restore dump 到新库:`docker exec -i nuankebao-postgres pg_restore -U nuankebao -d nuankebao --no-owner < /tmp/bbt-pre-rename.dump` |
| 5.7 | 验证: `docker exec nuankebao-postgres psql -U nuankebao -d nuankebao -c '\dt'` 必须看到 11 张表 |
| 5.8 | 验证: `docker exec nuankebao-postgres psql -U nuankebao -d nuankebao -c 'SELECT count(*) FROM "user";'` 应该返回 0 行 |

**⚠ §6.3 vs §6.5 冲突**: 主人 9-05 拍板"container_name / volume_name 保留 bbt-*",但 §6.5 说"代码默认切到 nuankebao,主人手工迁移"。**这两条对 DB container 互相矛盾**。我倾向 §6.5(更彻底,因为 DB 是数据层,不是系统代号),但需主人确认。

---

### 阶段 6: crontab + 路径回填(10 分钟)
**目的**: cron 引用的脚本路径都换成新目录

| 步骤 | 命令 |
|---|---|
| 6.1 | 编辑新 crontab(内容跟 `/tmp/crontab.bak` 一致,但所有 `/home/mm7/nuankebao-agent/` 换成 `/home/mm7/nuankebao-agent/`,日志 `/tmp/bbt-*.log` 换成 `/tmp/nuankebao-*.log`) |
| 6.2 | `crontab /tmp/nuankebao-crontab.txt` |
| 6.3 | `crontab -l \| grep bbt-agent` 必须 0 行 |

---

### 阶段 7: 启动 + 验证(20 分钟)
**目的**: 全栈起来 + 关键路径都通

| 检查 | 命令 | 期望 |
|---|---|---|
| 7.1 Postgres | `docker exec nuankebao-postgres pg_isready -U nuankebao -d nuankebao` | "accepting connections" |
| 7.2 Next.js | `systemctl status nuankebao-nextjs` | active running |
| 7.3 Tunnel | `systemctl status nuankebao-cloudflared` | active running |
| 7.4 Docker | `systemctl status nuankebao-stack` | active running |
| 7.5 **kill 旧 next dev** | `kill 132018` (cwd 指向老目录) | **5-10 秒断服** |
| 7.6 拉新 next dev | `systemctl --user daemon-reload && systemctl --user enable --now nuankebao-nextjs` | active running |
| 7.7 本机 | `curl -s -o /dev/null -w '%{http_code}\n' http://localhost:3003` | 200 或 307 |
| 7.8 公网 | `curl -s -o /dev/null -w '%{http_code}\n' https://nuankebao.tooyang.top` | 200 或 307 |
| 7.9 切临时隧道 | `sudo systemctl stop bbt-cloudflared` (PID 4303 退场) | 灰度切换 |
| 7.10 装命名隧道 | `sudo systemctl enable --now nuankebao-cloudflared` | active running |
| 7.11 公网仍通 | `curl -s -o /dev/null -w '%{http_code}\n' https://nuankebao.tooyang.top` | 仍 200/307 |
| 7.12 crontab | `crontab -l \| grep bbt-agent` | 0 行 |
| 7.13 文件残留 | `rg -l 'bbt-agent\|nuankebao-postgres\|nuankebao-web' /home/mm7/nuankebao-agent/ --hidden -g '!node_modules' -g '!.git' -g '!drizzle/meta' -g '!*.lock' -g '!CHANGELOG.md'` | 仅 CHANGELOG.md |
| 7.14 备份脚本 | `tools/nuankebao-backup.sh --dry-run` | 应通 |

---

### 阶段 8: 文档收尾(10 分钟)
- `AGENTS.md` §6 改成最终态(不再分"保留/已变更")
- `CHANGELOG.md` 加 `[0.3.0]` 段
- `README.md` 更新仓库地址(`/home/mm7/nuankebao-agent` → `/home/mm7/nuankebao-agent`)
- `PHYSICAL_OPS.md` 更新路径
- git commit: `chore(rename): full rename bbt-agent → nuankebao-agent (hostnames + DB + scripts + systemd)`

---

## 3. 风险矩阵

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| §6.3 vs §6.5 DB container 名冲突 | 已确认 | 名字不一致 | 阶段 5.3 主人拍 |
| Cloudflare DNS 未配 `nuankebao.tooyang.top` | 中 | 改名后公网断 | 阶段 0 G0-1 主人确认 |
| `nuankebao-postgres-data` volume 删错 | 低 | 数据全丢(W1 阶段 0 业务数据可接受) | 阶段 1.3 pg_dump 已备份 |
| mv 目录时 systemd unit 引用断 | 高 | service failed 短暂 | 阶段 3 一次性更新 |
| crontab 改错路径 | 低 | 备份/看门狗失败 | 阶段 1.2 备份原 crontab |
| APK 还在引用老 hostname | 中 | 销售员登录失败 | 主人确认是否需要新 build APK(本 SOP 不动 APK build,因 GitHub Actions 上跑) |

---

## 4. 不在本 SOP 范围

- ❌ 不重新 build Flutter APK(云上 GitHub Actions 触发,不在本机)
- ❌ 不改 Cloudflare Dashboard(DNS / Tunnel Public Hostname)(主人手工)
- ❌ 不改 Cloudflare Tunnel 命名/ID(只是从 `--url` 临时模式切到命名 `tunnel run` 模式)
- ❌ 不动 `tools/.claude/` / `tools/.codex/` 等 IDE 配置(如有)

---

## 5. Gate 总表

每阶段执行前/后,**主人必须拍板**:

| Gate | 内容 | 主人拍 |
|---|---|---|
| G0-1 | DNS `nuankebao.tooyang.top` 已配 | ☐ |
| G0-2 | Tunnel `a8957e6c...` 公共 hostname 含 nuankebao | ☐ |
| G0-3 | 当前无销售员/admin 在用 | ☐ |
| G0-4 | DB container 名改成 nuankebao-postgres(推翻 §6.3) | ☐ |
| G1 | pg_dump 看到 11 张表 | ☐ |
| G2 | mv 完成 | ☐ |
| G3 | systemd daemon-reload 完成 | ☐ |
| G4 | 替换完成,rg 残留 0 处 | ☐ |
| G5 | restore 后 11 张表都还在 | ☐ |
| G6 | crontab 0 残留 | ☐ |
| G7 | 7.7 / 7.8 / 7.11 都通 | ☐ |
| G8 | git commit + Cloudflare Dashboard 删 bbt.tooyang.top | ☐ |
