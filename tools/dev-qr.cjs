#!/usr/bin/env node
/* eslint-disable no-console */
/**
 * 暖客宝 (NuankeBao) 真机预览二维码生成器
 *
 * 用法:
 *   node tools/dev-qr.js --port 3010
 *   node tools/dev-qr.js --port 3010 --url /admin/customers
 *   node tools/dev-qr.js --port 3010 --host 192.168.1.100
 *   node tools/dev-qr.js --port 3010 --no-frame         # 只要裸 QR
 *   node tools/dev-qr.js --port 3010 --json             # 输出 { url, ip, port } JSON
 *
 * 设计原则 (AGENTS.md §3):
 *   - 自动选 LAN IP (跳过 docker0 / br-* / lo / VPN)
 *   - 终端输出彩框, 销售员/开发者扫码即看
 *   - TTY 检测, 非 TTY 自动降级到 --json (管道友好)
 *   - 不引入额外依赖 (复用 package.json 里的 qrcode)
 */
'use strict';

const os = require('os');
const fs = require('fs');
const path = require('path');
const QR = require('qrcode');

// ---------- ANSI 颜色 ----------
const C = {
  reset: '\x1b[0m',
  bold:  '\x1b[1m',
  dim:   '\x1b[2m',
  red:   '\x1b[31m',
  green: '\x1b[32m',
  yellow:'\x1b[33m',
  blue:  '\x1b[34m',
  magenta:'\x1b[35m',
  cyan:  '\x1b[36m',
  white: '\x1b[37m',
  bgBlue:'\x1b[44m',
  bgMagenta:'\x1b[45m',
};

// ---------- CLI 解析 ----------
function parseArgs(argv) {
  const args = { port: null, host: null, url: '', noFrame: false, json: false, title: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--port' || a === '-p') args.port = parseInt(argv[++i], 10);
    else if (a === '--host' || a === '-H') args.host = argv[++i];
    else if (a === '--url' || a === '-u') args.url = argv[++i];
    else if (a === '--no-frame') args.noFrame = true;
    else if (a === '--json') args.json = true;
    else if (a === '--title' || a === '-t') args.title = argv[++i];
    else if (a === '--help' || a === '-h') {
      console.log(fs.readFileSync(__filename, 'utf8').split('\n').slice(1, 14).join('\n').replace(/^\s*\* ?/gm, ''));
      process.exit(0);
    }
  }
  return args;
}

// ---------- LAN IP 智能选择 ----------
function pickLanIp(prefer) {
  if (prefer) return prefer;

  const ifaces = os.networkInterfaces();
  const candidates = [];

  // 收集所有 IPv4
  for (const [name, addrs] of Object.entries(ifaces)) {
    if (!addrs) continue;
    for (const a of addrs) {
      if (a.family !== 'IPv4' || a.internal) continue;
      const ip = a.address;

      // 跳过虚拟接口
      const lower = name.toLowerCase();
      if (lower === 'lo') continue;
      if (lower.startsWith('docker')) continue;
      if (lower.startsWith('br-')) continue;       // docker bridge
      if (lower.startsWith('veth')) continue;      // docker veth
      if (lower.startsWith('virbr')) continue;     // libvirt
      if (lower.startsWith('vmnet')) continue;     // vmware
      if (lower.startsWith('vboxnet')) continue;   // virtualbox
      if (lower.includes('tailscale')) continue;
      if (lower.includes('wg')) continue;          // wireguard
      if (lower.includes('tun') || lower.includes('tap')) continue;
      if (lower.includes('zt')) continue;          // zerotier

      // 评分
      let score = 0;
      if (ip.startsWith('192.168.')) score = 100;   // 家庭 LAN 最常见
      else if (ip.startsWith('10.')) score = 60;    // 内网 A 类
      else if (ip.startsWith('172.')) score = 50;   // 内网 B 类
      else score = 10;

      // 优先物理网卡 (en / eth / wlp / wlan)
      if (/^(en|eth|wlp|wlan)/.test(lower)) score += 30;

      candidates.push({ name, ip, score });
    }
  }

  if (candidates.length === 0) {
    throw new Error('找不到可用的 LAN IP (所有 IPv4 都被过滤了)');
  }

  candidates.sort((a, b) => b.score - a.score);
  return candidates[0].ip;
}

// ---------- QR 渲染 ----------
async function renderQr(text) {
  return QR.toString(text, {
    type: 'terminal',
    small: true,         // 用 ▀▄█ 块字符, 扫得更稳
    margin: 1,
    errorCorrectionLevel: 'M',
  });
}

// ---------- 终端宽度 ----------
function getTermWidth() {
  const cols = process.stdout.columns || 80;
  return Math.max(60, Math.min(cols, 120));
}

// ---------- 框线 ----------
function boxLine(content, width, align = 'left') {
  const pad = Math.max(0, width - content.length);
  if (align === 'center') {
    const l = Math.floor(pad / 2);
    const r = pad - l;
    return '│' + ' '.repeat(l) + content + ' '.repeat(r) + '│';
  }
  return '│' + content + ' '.repeat(pad) + '│';
}

function padQr(qrStr, width) {
  // QR 行去掉 ANSI 后宽度, 居中填充空格
  const stripAnsi = (s) => s.replace(/\x1b\[[0-9;]*m/g, '');
  return qrStr.split('\n').filter(l => l.length > 0).map(line => {
    const visible = stripAnsi(line).length;
    const pad = Math.max(0, width - visible);
    const l = Math.floor(pad / 2);
    const r = pad - l;
    return '│' + ' '.repeat(l) + line + ' '.repeat(r) + '│';
  });
}

// ---------- 主输出 ----------
async function printFramed({ title, url, port, ip, qr }) {
  const W = getTermWidth();
  const innerW = W - 4;  // 留两边 │ │
  const top    = '┌' + '─'.repeat(innerW + 2) + '┐';
  const middle = '├' + '─'.repeat(innerW + 2) + '┤';
  const bottom = '└' + '─'.repeat(innerW + 2) + '┘';

  const lines = [];
  lines.push(top);

  // 标题行
  const titleText = `${C.bold}${C.magenta}  暖客宝 (NuankeBao) 真机预览  ${C.reset}`;
  lines.push(boxLine(titleText, innerW + 2, 'left'));

  // 副标题
  const subtitle = `${C.dim}  Wellness Sales Staff · Mobile Preview${C.reset}`;
  lines.push(boxLine(subtitle, innerW + 2, 'left'));

  lines.push(middle);

  // URL (大, 显眼)
  const urlLabel = `${C.cyan}URL${C.reset}     ${C.bold}${C.green}${url}${C.reset}`;
  lines.push(boxLine(urlLabel, innerW + 2, 'left'));

  // IP + 端口 (分行, 方便复制)
  const ipLine = `${C.cyan}LAN IP${C.reset} ${C.bold}${ip}${C.reset}`;
  lines.push(boxLine(ipLine, innerW + 2, 'left'));

  const portLine = `${C.cyan}PORT${C.reset}   ${C.bold}${port}${C.reset}`;
  lines.push(boxLine(portLine, innerW + 2, 'left'));

  // 主机名 (参考)
  const hostLine = `${C.dim}HOSTNAME  ${os.hostname()}${C.reset}`;
  lines.push(boxLine(hostLine, innerW + 2, 'left'));

  lines.push(middle);

  // QR 居中
  lines.push(...padQr(qr, innerW));

  lines.push(middle);

  // 提示
  const tips = [
    `${C.yellow}📱 手机扫码 → 自动打开${C.reset}`,
    `${C.dim}• 手机需连同一 WiFi (${ip} 同网段)${C.reset}`,
    `${C.dim}• iOS Safari / 微信扫码均可${C.reset}`,
    `${C.dim}• 触屏测试 ≥ 44px, 弱网建议 Chrome DevTools 4x CPU 减速${C.reset}`,
    `${C.dim}• 端口冲突? 跑 ./tools/check-port.sh --find 3000 9000${C.reset}`,
  ];
  for (const t of tips) lines.push(boxLine(t, innerW + 2, 'left'));

  lines.push(bottom);

  console.log(lines.join('\n'));
}

// ---------- Main ----------
async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (!args.port) {
    console.error(`${C.red}✗ 必须指定 --port${C.reset}`);
    console.error(`${C.dim}  用法: node tools/dev-qr.js --port 3010${C.reset}`);
    process.exit(2);
  }

  let ip;
  try {
    ip = pickLanIp(args.host);
  } catch (e) {
    console.error(`${C.red}✗ ${e.message}${C.reset}`);
    process.exit(2);
  }

  const url = `http://${ip}:${args.port}${args.url || ''}`;
  const qr = await renderQr(url);

  if (args.json) {
    console.log(JSON.stringify({ url, ip, port: args.port, hostname: os.hostname() }, null, 2));
    return;
  }

  if (args.noFrame) {
    console.log(qr);
    console.log(`\n${C.green}${url}${C.reset}\n`);
    return;
  }

  await printFramed({
    title: args.title || 'NuankeBao',
    url,
    port: args.port,
    ip,
    qr,
  });
}

main().catch((e) => {
  console.error(`${C.red}✗ QR 生成失败: ${e.message}${C.reset}`);
  process.exit(1);
});
