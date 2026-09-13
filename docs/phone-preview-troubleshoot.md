# 手机真机预览 404 排查清单 (Phone Preview 404 Troubleshooting)

> 暖客宝 dev server 在 LAN 跑 (例: `http://192.168.1.200:3010`),
> 手机扫码后 404. 按本清单**自下而上**排查, 5 分钟定位.

## TL;DR — 90% 是这两条

| # | 原因 | 现象 | 修法 |
|---|---|---|---|
| 1 | **手机没连同 WiFi** (用流量) | 浏览器报 `无法连接` / `Safari 无法打开页面` | 切到办公室 WiFi |
| 2 | **手机浏览器旧 cache** | 即使服务器修了, 浏览器还显示旧 404 页面 | **无痕模式** 重试 (最快) |

剩下 10%: DNS 缓存 / 路由 AP 隔离 / 公司 WiFi 客户端隔离 → 看 §5

---

## §1. 服务器端先确认 (3 条命令)

在**服务器** (mm7 mini) 上跑, 全绿才轮到排查手机:

```bash
# 1. dev server 还活着?
ps -ef | grep "next dev.*3010" | grep -v grep | head -1
#   期望: 看到一行 next dev 进程, 有 PID

# 2. 端口 3010 在监听?
ss -tlnp 2>/dev/null | grep ":3010 "
#   期望: LISTEN ... 0.0.0.0:3010 (不要只看到 127.0.0.1)

# 3. 从服务器 curl 自己, 看 200/302
curl -s -o /dev/null -w "%{http_code}\n" http://192.168.1.200:3010/admin
#   期望: 200 (DEV_SKIP_AUTH=1 已开) 或 302→/login
```

✅ 全绿 → §2
❌ 任一红 → `./tools/start-dev.sh 3010` 重启

---

## §2. 网络层 — 手机和服务器同网段?

### 2.1 看手机 IP
- **iOS**: 设置 → WiFi → 点当前连接的 `ⓘ` → 看 IP 地址
- **Android**: 设置 → 网络 → WiFi → 当前 SSID → 看 IP

期望手机 IP: `192.168.1.xxx` (同 /24 段)

### 2.2 最快测: 手机浏览器开 `http://192.168.1.200:3010/api/health`
期望看到:
```json
{"status":"healthy","checks":{"db":"ok"},"version":"0.1.0",...}
```

- ✅ 看到 JSON → 网络通, 跳 §3
- ❌ `Safari 无法打开页面` / `ERR_CONNECTION_REFUSED` → 网络层问题

### 2.3 网络层问题排查 (按概率)

| 现象 | 原因 | 修法 |
|---|---|---|
| `无法连接` + 手机 IP 是 `192.168.1.x` 但服务器 `192.168.1.200` | **WiFi 客户端隔离** (公司/公共 WiFi 常见) | 换手机 4G 热点 或 用 USB 共享网络 |
| `无法连接` + 手机 IP 是 `10.x.x.x` 或 `172.x.x.x` | **手机在不同网段** (访客网络) | 切到主人办公室 WiFi |
| `Safari 无法打开页面 因为服务器已停止响应` | 服务器防火墙挡了 3010 | 跑 `sudo ufw status` 看 (主人自己排查, 不在 agent 范围) |
| `域名解析失败` (用域名时) | 手机 DNS 不认 | 改用 IP 直连 `192.168.1.200:3010` |

---

## §3. 应用层 — 缓存/Cookie

### 3.1 最快修: 无痕模式 (90% 命中)

- **iOS Safari**: 点右下角 tab 按钮 → 点左下角 "起始页" 或 `Tab Groups` → `私密浏览`
- **Chrome Android**: 点右上角 `⋮` → `新建无痕式标签页`
- **微信**: 长按扫一扫结果 → `在浏览器中打开` (绕开微信 X5 内核缓存)

### 3.2 仍有 cache: 清指定域的 cookie

只在以下情况做:
- 之前手机访问过 `nuankebao.tooyang.top` (公网域名) — Auth.js 的 `__Secure-authjs.callback-url` cookie 可能还指向那里
- 用了 PWA / 加到主屏幕的暖客宝

清法:
- **iOS Safari**: 设置 → Safari → 高级 → 网站数据 → 搜索 `nuankebao` → 滑动删除
- **Android Chrome**: 设置 → 隐私和安全 → 清除浏览数据 → 选 "Cookie 和网站数据" + "缓存的图片和文件"

### 3.3 硬清: 删 PWA / 卸载重装

如果之前把暖客宝 "添加到主屏幕" 当 PWA 用:
- 长按主屏幕图标 → 删应用
- 重扫 QR, 浏览器直接打开 (不要再添加到主屏)

---

## §4. 浏览器层 — 看实际请求

### 4.1 Safari (iOS): 看 console

1. 设置 → Safari → 高级 → `Web 检查器` 打开
2. Mac 装 Apple Configurator 或用 Safari 远程调试
3. (复杂) 跳过, 用 §4.2

### 4.2 Chrome Android: 远程调试

1. 手机开 `chrome://inspect/#devices` (在 PC Chrome 输)
2. 手机 USB 连 PC, 同意调试
3. PC Chrome DevTools → Network 面板 → 看手机请求

期望看到:
```
GET http://192.168.1.200:3010/admin → 200 (DEV_SKIP_AUTH=1)
```
- ✅ 200 → 客户端侧 cache, 清掉就行
- ❌ 404 → 服务器端问题, 回头看 §1

---

## §5. 罕见原因 (处理过前 4 段还 404 才看)

### 5.1 公司 AP 隔离
- 表现: 同 WiFi 段内设备互 ping 不到
- 测: 手机 ping 服务器 (要装 `Network Analyzer` / `HE Network Tools` app)
- 修: 找 IT 开端口, 或换手机 4G 热点共享给 PC

### 5.2 服务器防火墙 (Linux iptables / ufw)
- 表现: 局域网内其他 PC curl 也是 connection refused
- 测 (主人):
  ```bash
  sudo iptables -L -n | grep 3010   # 应有 ACCEPT
  sudo ufw status                    # 3010 应在白名单
  ```
- 修: 主人手动放行, agent 不擅改 (AGENTS.md §3 红线)

### 5.3 Docker / VPN / tailscale 抢了路由
- 表现: 手机能上公网, 但访问 192.168.1.x 走错网关
- 测: 手机装 `Net Analyzer` → traceroute 192.168.1.200 → 看第一跳是不是 192.168.1.1
- 修: 关掉手机 VPN / 公司 MDM profile

### 5.4 端口被服务器 NAT 改成别的
- 表现: 服务器 `ss -tlnp` 显示 3010 在听, 但 `192.168.1.200:3010` 不通
- 原因: 路由器端口转发没配, 或服务器在 NAT 后
- 修: 改用服务器本来的入网 IP (问网络管理员) 或 配路由器

---

## §6. 一键自我诊断 (手机侧)

把下面 URL 发到手机微信, 在微信里点开 (微信会当外链处理, 失败时报错更详细):

```
http://192.168.1.200:3010/api/health
```

期望看到 JSON。失败的话微信会显示:
- `无法连接` → §2
- `404 Not Found` → 服务器端, 回 §1
- `500 Server Error` → 服务器端 bug, 看 `/tmp/bbt-dev.log`
- 一直在转圈 → 网络层

---

## §7. 真·兜底: SSH 端口转发 (100% 命中)

**任何方法都失败时的最后手段**:

1. 主机 (主人 PC) SSH 端口转发到服务器:
   ```bash
   ssh -L 8080:localhost:3010 mm7@192.168.1.200
   ```
2. PC 浏览器开 `http://localhost:8080` (走 SSH 隧道, 不过路由器)
3. **手机不行** — 除非 PC 起热点 + 手机连 PC, 然后手机用 PC 的代理

如果 PC 浏览器都 404 → 服务器端 100% 有问题, 回头看 §1.

---

## §8. 反馈给 agent 时附这 3 条

如果上述都试过还不行, 把下面 3 条贴回来:

1. `curl -s -o /dev/null -w "%{http_code}\n" http://192.168.1.200:3010/admin` 在服务器跑的结果
2. 手机访问 `http://192.168.1.200:3010/api/health` 的实际截图/错误文字
3. 手机 IP (设置→WiFi→当前 SSID→IP)

agent 拿到这 3 条能秒定位.

---

**vibe**: 暖客宝销售员实测手机**都很旧** (iPhone 11/华为畅享), WiFi 信号弱.
本 SOP 第 §3.1「无痕模式」是 90% 命中解, 先试这个.
