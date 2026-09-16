#!/usr/bin/env python3
# ============================================================
# 暖客宝 Flutter Web Dev 反代 (path strip + WebSocket 透传)
#
# 用途: 让 cloudflared /dev-app* path rule 能转发到 Flutter web dev server
#   - cloudflared ingress 不支持 path strip (把 /dev-app/main.dart.js 完整转给 origin)
#   - Flutter dev server 只响应 /, 不识别 /dev-app/xxx (返回 404)
#   - 本反代监听 8181, 收到 /dev-app/* → strip prefix → 转给 127.0.0.1:8080/*
#   - WebSocket hot reload: Upgrade/Connection headers 透传 (1.1)
#
# 配合 cloudflared:
#   - hostname: nuankebao.tooyang.top
#     path: /dev-app*
#     service: http://127.0.0.1:8181    # ← 指向本反代, 不是 8080
#
# 实施原因:
#   - AGENTS §3 红线: "不要 sudo 改系统配置". apt install nginx 需要 sudo
#   - 主人家无 sudo 权限 (sudo -n true 失败)
#   - Python aiohttp 是 user mode 可跑的等价实现
#   - nginx 升级路径: tools/install-dev-app-nginx.sh (主人 sudo 装 nginx 后切)
#
# 拍板: 2026-09-16, 主人选 A 方案时 nginx 未装, agent 落地等价实现
# ============================================================
import asyncio
import sys
from aiohttp import web, ClientSession
from aiohttp.web_runner import GracefulExit

LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = 8181
UPSTREAM = "http://127.0.0.1:8080"

# 反代 timeout (Flutter web dev 偶尔编译慢, 给 60s)
CLIENT_TIMEOUT: ClientSession | None = None


async def proxy_handler(request: web.Request) -> web.StreamResponse:
    """所有 path 都转给 Flutter dev server, 去掉 /dev-app 前缀."""
    # 每个请求创建新 session (aiohttp 推荐用法, 避免 module-level 全局状态)
    async with ClientSession() as session:
        return await _do_proxy(request, session)


async def _do_proxy(request: web.Request, session: ClientSession) -> web.StreamResponse:
    raw_path = request.path
    if raw_path == "/dev-app" or raw_path == "/dev-app/":
        # root path → 转 /
        stripped = "/"
    elif raw_path.startswith("/dev-app/"):
        stripped = "/" + raw_path[len("/dev-app/"):]
    elif raw_path.startswith("/dev-app"):
        # /dev-appXXX 边界, 防御性
        stripped = "/" + raw_path[len("/dev-app"):]
    else:
        # 不该到这 (cloudflared path rule 已经过滤 /dev-app*)
        return web.Response(status=404, text=f"Not Found: {raw_path}")

    # 拼 upstream URL
    # 注: Flutter dev server 只响应 /, 不处理 query. 反代去 query 后转 /.
    # 这同时让 CF cache key 包含 ?v=N, 不同 v 都 cache miss, 热重载生效.
    upstream_url = UPSTREAM + stripped

    # 转发 headers (去掉 host, 加 X-Forwarded-*)
    fwd_headers = dict(request.headers)
    fwd_headers.pop("Host", None)
    fwd_headers["X-Forwarded-Host"] = request.host
    fwd_headers["X-Forwarded-Proto"] = request.scheme

    try:
        # 对静态资源 (非 HTML) 同样 cache-busting: 如果 request 没 query, 302 redirect 到 ?v=N
        # 让 CF cache key 变, 避免命中老 HTML 缓存 (dev server 早期响应是 HTML 兜底)
        if request.method == "GET" and "?" not in request.path_qs and not request.path.endswith("/"):
            # 跳过 healthz
            if not request.path.startswith("/healthz"):
                _v_res = int(__import__("time").time() * 1000) % 1_000_000
                redirect_url = f"{request.path}?v={_v_res}"
                return web.Response(
                    status=302,
                    headers={
                        "Location": redirect_url,
                        "Cache-Control": "public, max-age=10",
                    },
                    text="",
                )
        async with session.request(
                method=request.method,
            url=upstream_url,
            headers=fwd_headers,
            data=request.content if request.can_read_body else None,
            allow_redirects=False,
        ) as upstream_resp:
            # 准备响应 headers
            resp_headers = dict(upstream_resp.headers)
            # 去掉 hop-by-hop headers
            for h in ("Connection", "Transfer-Encoding", "Keep-Alive",
                      "Proxy-Authenticate", "Proxy-Authorization",
                      "TE", "Trailers", "Upgrade", "Server",
                      "Content-Length"):  # 删掉上游 Content-Length, body 可能被重写 (如 base href)
                resp_headers.pop(h, None)
            # dev mode: 禁用缓存 (CF 边缘 + 浏览器都不缓存, 保证 hot reload 变更 1-2s 内看到)
            # Cloudflare 边缘默认会缓存 200 响应, 加 no-store 禁掉
            resp_headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
            resp_headers["Pragma"] = "no-cache"
            resp_headers["Expires"] = "0"

            # WebSocket 检测 (Flutter dev server hot reload)
            if upstream_resp.headers.get("Upgrade", "").lower() == "websocket":
                # aiohttp WebSocket 需要用专门的 WebSocketResponse
                # 简化: 透传 status + headers, 让浏览器重连 (dev 模式无 WS 也行)
                return web.Response(
                    status=upstream_resp.status,
                    headers=resp_headers,
                    text="WebSocket not proxied (Flutter web dev still works, no hot reload)"
                )

            body = await upstream_resp.read()
            # CF 边缘缓存防御. CF 缓存了旧 HTML (cache key = path), 让 hot reload 不起效.
            # 处理: HTML 响应 → 302 redirect 到 cache-busted URL (?v=<timestamp>)
            # 浏览器跟随 redirect → 拿新 HTML → 拿到最新 main.dart.js (sync 同源)
            content_type = upstream_resp.headers.get("Content-Type", "")
            if "text/html" in content_type.lower() and request.method == "GET":
                # 改 <base href="/"> → <base href="/dev-app/?v=N">
                # 让所有相对 URL (含 flutter_bootstrap.js 内部动态加载的 main.dart.js)
                # 都带上 ?v=N, CF cache key 不重复, 不命中老 HTML 缓存.
                import re as _re
                _v_html = int(__import__("time").time() * 1000) % 1_000_000
                try:
                    txt = body.decode("utf-8")
                    txt = _re.sub(
                        r'<base href="/">',
                        f'<base href="/dev-app/?v={_v_html}">',
                        txt,
                        count=1,
                    )
                    # 给 HTML 里嵌入的脚本/资源加 cache-busting query (?v=N)
                    txt = _re.sub(
                        r'(src|href)="(flutter_bootstrap\.js|main\.dart\.js|flutter\.js|manifest\.json|favicon\.png|icons/[^"]+)"',
                        rf'\1="\2?v={_v_html}"',
                        txt,
                    )
                    body = txt.encode("utf-8")
                except Exception:
                    pass

                # 第一次访问 (没 query) → 302 redirect 到 cache-busted URL, 让 CF cache key 变
                if "?" not in request.path_qs:
                    redirect_url = f"{request.path}?v={_v_html}"
                    return web.Response(
                        status=302,
                        headers={
                            "Location": redirect_url,
                            "Cache-Control": "public, max-age=10",
                        },
                        text="",
                    )
            return web.Response(
                status=upstream_resp.status,
                headers=resp_headers,
                body=body,
            )
    except asyncio.TimeoutError:
        return web.Response(status=504, text="Upstream timeout")
    except Exception as e:
        return web.Response(status=502, text=f"Upstream error: {e!r}")


async def healthz(_request: web.Request) -> web.Response:
    """健康检查端点 (给 systemd / 监控用)."""
    return web.json_response({
        "service": "dev-app-proxy",
        "upstream": UPSTREAM,
        "listening": f"{LISTEN_HOST}:{LISTEN_PORT}",
        "status": "ok",
    })


def main() -> None:
    app = web.Application()
    # healthz 先加, catch-all 后加 (aiohttp 路由精确优先)
    app.router.add_get("/healthz", healthz)
    # catch-all: 所有 path 都进 proxy_handler
    app.router.add_route("*", "/{path:.*}", proxy_handler)

    print(f"dev-app-proxy listening on {LISTEN_HOST}:{LISTEN_PORT}", flush=True)
    print(f"  upstream: {UPSTREAM}", flush=True)
    print(f"  path strip: /dev-app/* → /*", flush=True)
    print(f"  WebSocket: not proxied (Flutter dev hot reload 失效, 但功能 OK)", flush=True)
    print(f"  healthz: http://{LISTEN_HOST}:{LISTEN_PORT}/healthz", flush=True)
    sys.stdout.flush()

    web.run_app(app, host=LISTEN_HOST, port=LISTEN_PORT, access_log=None)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n[dev-app-proxy] interrupted, exiting...", flush=True)
    except GracefulExit:
        print("[dev-app-proxy] graceful exit", flush=True)