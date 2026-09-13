# 安全与合规方案

> 养生行业 + 高敏感健康数据 = 合规底线严格
> 核心法:**《个人信息保护法》(PIPL)** + **《数据安全法》** + **《网络安全法》**

---

## 1. 数据分级

| 级别 | 字段 | 处理 |
|---|---|---|
| 🔴 极高敏感 | 客户疾病史 / 健康状态 / 既往病史 / 心理状态 | pgcrypto 字段加密 + 审计 + 最小权限 |
| 🟠 高敏感 | 客户手机号 / 联系人电话 / 家庭住址 | pgcrypto 加密 + 审计 |
| 🟡 中敏感 | 客户姓名 / 性别 / 出生年 / 消费记录 | 明文 + 审计 |
| 🟢 普通 | 用户名 / 角色 / UI 偏好 | 明文 |

## 2. 加密方案

### 2.1 字段级加密(应用层 AES-256-CBC)

```typescript
// src/lib/crypto/field.ts
import crypto from 'node:crypto';

const ALGORITHM = 'aes-256-cbc';
// 密钥从环境变量读,32 bytes (256 bits)
const KEY = Buffer.from(process.env.PGCRYPTO_KEY!, 'hex');

export function encryptField(plaintext: string): string {
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv(ALGORITHM, KEY, iv);
  const encrypted = Buffer.concat([
    cipher.update(plaintext, 'utf8'),
    cipher.final(),
  ]);
  // iv + ciphertext,base64 存储
  return Buffer.concat([iv, encrypted]).toString('base64');
}

export function decryptField(ciphertext: string): string {
  const data = Buffer.from(ciphertext, 'base64');
  const iv = data.subarray(0, 16);
  const ct = data.subarray(16);
  const decipher = crypto.createDecipheriv(ALGORITHM, KEY, iv);
  return Buffer.concat([
    decipher.update(ct),
    decipher.final(),
  ]).toString('utf8');
}
```

### 2.2 查询用 hash 索引

```typescript
import crypto from 'node:crypto';

export function hashForLookup(plaintext: string): string {
  // MD5 用于查找索引(非安全目的,SHA-256 也可)
  return crypto.createHash('md5').update(plaintext).digest('hex');
}
```

存储时同时存:
- `phone_encrypted` (加密字段)
- `phone_hash` (md5 用于查询)

查询时用 hash 找到记录,再解密字段。

### 2.3 数据库层加密(透明加密 / TDE) — Phase 2

Postgres 自带 `pgcrypto` 扩展 + 表空间加密:

```sql
-- 应用层加密 + 数据库文件加密(双层)
-- 文件加密走 LUKS (Linux Unified Key Setup)
```

**MVP 阶段只做应用层加密**,数据库文件加密 Phase 2。

### 2.4 备份加密

```bash
# tools/backup.sh
pg_dump $DATABASE_URL | gpg --symmetric --cipher-algo AES256 \
  --passphrase "$BACKUP_PASSPHRASE" \
  > backups/backup-$(date +%Y%m%d).sql.gpg
```

备份文件本身加密,即使磁盘被偷也安全。

## 3. 密钥管理

### 3.1 密钥存储

- **绝不**进 git
- **绝不**进 `.env` (用 `.env.local` 或 Docker secrets)
- 主人自有服务器 = 物理隔离,密钥放 `/etc/bbt/secrets/`(仅 root + bbt 用户可读)

```
/etc/bbt/secrets/
├── pgcrypto.key         # 字段加密密钥 (32 bytes hex)
├── db-password          # Postgres 密码
├── auth-secret          # Auth.js secret
└── aliyun-sms-key       # 阿里云短信 API key
```

文件权限:`chmod 600 /etc/bbt/secrets/*`,owner `bbt:bbt`。

### 3.2 密钥轮换

| 密钥 | 轮换周期 | 操作 |
|---|---|---|
| PGCRYPTO_KEY | 每年 | 重加密所有加密字段(运维脚本,详见 SOP) |
| DB password | 半年 | `ALTER USER nuankebao PASSWORD '...'` |
| Auth.js secret | 半年 | 重启服务,所有 session 失效 |
| 阿里云 SMS key | 1 年 | 在阿里云控制台重生成 |

### 3.3 灾难恢复

- 密钥本身备份到 U 盘(主人保管,异地)
- 异地备份:U 盘每月一次放到第二个物理位置

## 4. 访问控制

### 4.1 角色

```sql
CREATE TYPE user_role AS ENUM ('admin', 'manager', 'sales');
```

| 角色 | 权限 |
|---|---|
| **admin** | 全部 + 用户管理 + 审计日志 |
| **manager** | 全部业务数据 + 报表(不能看审计日志) |
| **sales** | 自己创建的客户 + 自己负责的跟进任务 |

### 4.2 行级安全 (RLS) — Phase 2

```sql
-- sales 角色只能看自己创建的客户
ALTER TABLE customer ENABLE ROW LEVEL SECURITY;
CREATE POLICY sales_own_customer ON customer
  FOR SELECT TO sales
  USING (created_by = current_setting('app.current_user_id')::BIGINT);
```

**MVP 阶段**走应用层校验(W2-W3 实现),RLS 是 Phase 2 加固。

## 5. 审计日志

### 5.1 触发器自动写

任何 `INSERT / UPDATE / DELETE` 在敏感表:

```sql
CREATE OR REPLACE FUNCTION audit_trigger() RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO audit_log (table_name, record_id, operation, user_id, changed_fields, ip_address)
  VALUES (
    TG_TABLE_NAME,
    COALESCE(NEW.id, OLD.id),
    TG_OP,
    current_setting('app.current_user_id', true)::BIGINT,
    CASE TG_OP
      WHEN 'INSERT' THEN to_jsonb(NEW)
      WHEN 'UPDATE' THEN to_jsonb(NEW) - to_jsonb(OLD)
      WHEN 'DELETE' THEN to_jsonb(OLD)
    END,
    current_setting('app.client_ip', true)::INET
  );
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- 挂触发器
CREATE TRIGGER customer_audit AFTER INSERT OR UPDATE OR DELETE ON customer
  FOR EACH ROW EXECUTE FUNCTION audit_trigger();
-- 同上:wellness_record, interaction, follow_up_task, user
```

### 5.2 应用层设置 session 变量

```typescript
// src/lib/db/index.ts
import { db } from './client';

export async function withAuditContext<T>(
  userId: bigint,
  ipAddress: string,
  fn: (tx: typeof db) => Promise<T>
): Promise<T> {
  return await db.transaction(async (tx) => {
    await tx.execute(sql`SET LOCAL app.current_user_id = ${userId.toString()}`);
    await tx.execute(sql`SET LOCAL app.client_ip = ${ipAddress}`);
    return await fn(tx);
  });
}
```

### 5.3 审计日志查询 (仅 admin)

管理员可以查:
- 谁在什么时候看了哪个客户的健康记录
- 谁修改了什么字段
- 谁删除了什么数据

保留期:**2 年**(符合《个保法》要求)。

## 6. 网络安全

### 6.1 HTTPS 强制

- Let's Encrypt 证书(免费)
- Nginx 反向代理 + HTTP → HTTPS 重定向
- HSTS 头(`Strict-Transport-Security: max-age=31536000`)

### 6.2 防火墙

服务器端:

```bash
# 只开 80/443 (web) 和 22 (SSH)
sudo ufw default deny incoming
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow from <主人固定IP> to any port 22
```

**Postgres 端口 5432 不对外开放**,只 docker 内网访问。

### 6.3 SSH 加固

```bash
# /etc/ssh/sshd_config
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AllowUsers bbt
```

主人 → 服务器走密钥认证。

### 6.4 速率限制

Next.js middleware:

```typescript
// src/middleware.ts
import { Ratelimit } from '@upstash/ratelimit';
// 登录:5 次/分钟/IP
// API:60 次/分钟/用户
```

## 7. 数据生命周期

### 7.1 创建

- 客户录入 → 自动加密敏感字段
- 养生记录 → 自动写审计

### 7.2 修改

- 所有修改走审计
- 加密字段修改 = 重新加密(IV 自动变化)

### 7.3 删除

- 软删除 (`deleted_at`) = 默认行为
- 硬删除 = 极少见,需 admin 审批 + 二次确认
- 客户硬删除 = 同时清理所有关联养生记录 + 联系记录(法律要求"被遗忘权")

### 7.4 归档

- 5 年前的客户 / 养生记录 → 归档表(冷数据)
- 仍在审计日志可查

## 8. 合规清单

### 8.1 《个人信息保护法》(PIPL) 关键条款

| 条款 | 要求 | 实现 |
|---|---|---|
| 第 13 条 | 知情同意 | 登录后弹窗告知"我们如何处理您的数据" |
| 第 17 条 | 透明度 | 隐私政策页面 `/privacy` |
| 第 24 条 | 自动化决策透明 | AI 话术生成时明示"AI 生成,仅供参考" |
| 第 44 条 | 数据主体权利 | 用户可导出自己的数据, 可申请删除 |
| 第 47 条 | 删除义务 | 客户硬删除时清空所有 PII |

### 8.2 数据主体权利实现

| 权利 | 实现 |
|---|---|
| **知情权** | `/privacy` 页面 + 注册时同意 |
| **访问权** | 客户可看自己的所有数据 `/api/customer/me/data` |
| **更正权** | 用户可改自己的信息 |
| **删除权** | admin 可触发硬删除 |
| **数据可携** | `/api/customer/me/export` 返回 JSON |
| **拒绝自动化决策** | AI 建议可关闭,只用人工 |

## 9. 备份与灾难恢复

### 9.1 备份策略

```
每日:
  - 全量数据库备份(凌晨 3 点)
  - 加密 (gpg AES-256)
  - 保留 30 天
  - 上传到第二台机器 (rsync) 或 U 盘

每周:
  - 全量 + 周增量
  - 保留 12 周

每月:
  - 归档备份(冷存储)
  - 保留 5 年(合规)
```

### 9.2 备份恢复演练

每季度演练一次:
- 选一个 30 天前的备份
- 在测试环境恢复
- 验证数据完整 + 应用能起来
- 记录演练结果 → 主人 review

## 10. 安全事件响应

### 10.1 事件分类

| 级别 | 定义 | 响应时间 |
|---|---|---|
| 🔴 P0 | 数据泄露 / 系统被入侵 | 立即(24h 内) |
| 🟠 P1 | 单个用户异常 / 越权访问 | 4h 内 |
| 🟡 P2 | 一般 bug / 配置错误 | 24h 内 |

### 10.2 应急流程

```
P0 事件:
1. 立即停服(防止扩散)
2. 主人通报 + 全员通知
3. 取证(日志 / 数据库快照)
4. 修复 + 重启服务
5. 事后报告(72h 内)
6. 改进 SOP + 主人 review
```

## 11. 安全审计清单

每月/季度自检:

- [ ] `pnpm audit`(npm 依赖漏洞扫描)
- [ ] `docker scan`(镜像扫描)
- [ ] 数据库用户权限最小化检查
- [ ] 日志异常检查(failed login, 异常 IP)
- [ ] 备份恢复演练(季度)
- [ ] 密钥轮换检查
- [ ] 审计日志清理(超 2 年的归档)

## 12. 第三方依赖安全

### 12.1 不允许引入

- ❌ 任何 AGPL 协议包(底座选型已排除)
- ❌ 任何 GPL 强 copyleft 包(同上)
- ❌ 任何调用境外 API 的 AI SDK(数据出境)
- ❌ 任何含已知 CVE 高危漏洞的包

### 12.2 引入新依赖时

```bash
# 1. 检查协议
pnpm info <pkg> license

# 2. 检查漏洞
pnpm audit
# 或
npx snyk test

# 3. 检查维护活跃度
# GitHub 上最近 commit < 3 个月 + issues 有人回应

# 4. 主人审批(写在 commit message 里)
git commit -m "deps: add zod for schema validation (MIT, 维护活跃)"
```

## 13. 文档与培训

### 13.1 必读文档

- `/docs/security-compliance.md`(本文件)
- `/tools/SOP.md`(运维 SOP,W5 写)
- `/docs/deploy.md`(部署文档,W5 写)

### 13.2 用户培训

销售 / 店长培训内容:
- 数据录入规范(什么字段不能存)
- 密码安全(不能告诉别人)
- 发现异常如何报告

---

## 决策记录

**2026-09-03**:本方案由主人拍板采纳,作为 Phase 1 MVP 的安全合规基线。Phase 2 / Phase 3 增量加固。