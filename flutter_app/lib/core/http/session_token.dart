// ============================================
// 登录态工具 (纯函数, 无网络无插件 → 可单测)
// ============================================
// 用途:
//   1. 解出 JWT 的 exp → 「我的 → 网络自检」里显示"登录有效期至 X" (主人 2026-09-20 要看)
//   2. 判断本地存的 token 是不是**明显过期** (过期了就别再拿它去打接口, 免得满屏 401)
//
// 边界:
//   - Auth.js 的 token 是加密 JWE (5 段, A256CBC-HS512), **解不开 payload** → 返回 null,
//     这时客户端不做任何判断 (由服务端决定), 只显示"有效期待确认"
//   - 只做 base64url 解析, 不验签 (验签是服务端的活; 客户端读了也改不了)

import 'dart:convert';

/// JWT/JWE 的段数: JWS = 3 段 (可解 payload), JWE = 5 段 (加密, 解不开)
int sessionTokenSegments(String token) => token.split('.').length;

/// 从 token 里解出过期时间 (拿不到就 null)
DateTime? sessionExpiry(String? token) {
  if (token == null || token.isEmpty) return null;
  final parts = token.split('.');
  // 只有 JWS (3 段) 的 payload 是 base64 明文; JWE (5 段) 解不开
  if (parts.length != 3) return null;

  try {
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    while (payload.length % 4 != 0) {
      payload += '=';
    }
    final decoded = jsonDecode(utf8.decode(base64.decode(payload)));
    if (decoded is! Map) return null;
    final exp = decoded['exp'];
    if (exp is num) {
      return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
    }
  } catch (_) {
    return null;
  }
  return null;
}

/// 本地 token 是否**确定**已过期 (拿不到 exp → false = 不敢下结论, 交给服务端)
bool isSessionDefinitelyExpired(String? token, {DateTime? now}) {
  final exp = sessionExpiry(token);
  if (exp == null) return false;
  return exp.isBefore(now ?? DateTime.now());
}

/// 给用户看的一句话 (网络自检里显示)
String sessionExpiryLabel(String? token) {
  final exp = sessionExpiry(token);
  if (exp == null) {
    // JWE (Auth.js 默认加密) 解不开 → 说人话, 别让用户以为坏了
    return '已记住登录 (长期有效, 具体到期由服务器校验)';
  }
  String two(int n) => n.toString().padLeft(2, '0');
  final days = exp.difference(DateTime.now()).inDays;
  final date = '${exp.year}-${two(exp.month)}-${two(exp.day)}';
  if (days < 0) return '登录已过期 ($date), 请重新登录';
  if (days > 365) return '已记住登录, 有效期至 $date (无需重复登录)';
  return '已记住登录, 有效期至 $date (还有 $days 天)';
}
