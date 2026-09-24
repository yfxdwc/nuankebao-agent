// ============================================
// FollowUpService 契约测试 (2026-09-24 用户反馈)
//
// 主人 2026-09-24 反馈: 客户详情「跟进任务」点「标记完成」→ 后端 400。
//   服务端日志实证: PATCH /api/follow-ups/38 400 (两次)。
//
// 根因 (双线):
//   后端契约 (src/app/api/follow-ups/[id]/route.ts::CompleteSchema) 只接受
//     { action: 'complete' | 'cancel', notes?: string }
//   老 Flutter FollowUpService 发的是
//     complete(id, {notes}) → { status: 'done', completedNotes: notes }
//     cancel(id)             → { status: 'cancelled' }
//   → 后端 Zod 拒, 400, 客户端看到 "ERR 400"。
//
// 本测试守契约 (反向断言 — 旧错形状回归):
//   · 发出去必须是 { action: 'complete' | 'cancel' } (web 同)
//   · 带 notes → body 含 'notes'; 不带 → **不**含 'notes' 键 (避免空字符串污染)
//   · 关键: body **不**含旧字段 'status' / 'completedNotes'
//
// 复盘: 改本测试任何断言前必须同步对照
//   · 后端 Zod schema (route.ts::CompleteSchema)
//   · web 端 complete-follow-up-button.tsx (fetch shape)
// 三者必须一字对得上, 否则又会回到 "客户端发 Zod 拒" 循环。
//
// 跑: cd flutter_app && flutter test test/follow_up_service_test.dart
// ============================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuankebao/core/services/api.dart';

/// 抓包 adapter: 收集 (method, path, body), 用对应 JSON 响应。
///
/// dio 5.x 默认 transformer 会把 `data: Map` JSON-编码, 字节经 `requestStream` 发出;
/// 故 `options.data` 仍是原 Map (未序列化), 但**真载荷**看 stream 更稳。
/// 两者都收一份, 测试里**优先读 bodyJson** (stream 解析), options.data 作对照。
class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter(this.responsePayload);
  final Map<String, dynamic> responsePayload;

  String? capturedMethod;
  String? capturedPath;
  Object? capturedOptionsData;
  Map<String, dynamic>? capturedBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    capturedMethod = options.method;
    capturedPath = options.path;
    capturedOptionsData = options.data;
    if (requestStream != null) {
      final chunks = <int>[];
      await for (final chunk in requestStream) {
        chunks.addAll(chunk);
      }
      if (chunks.isNotEmpty) {
        final raw = utf8.decode(chunks, allowMalformed: true);
        try {
          capturedBody = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {
          capturedBody = null;
        }
      }
    }
    return ResponseBody.fromString(
      jsonEncode(responsePayload),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 构造一个返回完整 FollowUpTask 形状 (与 src/lib/db/queries/follow-up-task.ts 一致)
Map<String, dynamic> _completeResponsePayload() => {
      'id': '38',
      'customerId': 'c-123',
      'dueAt': '2026-09-24T09:00:00.000Z',
      'reason': 'smoke 契约验证 (可删)',
      'aiSuggestion': null,
      'status': 'done',
      'completedAt': '2026-09-24T09:30:00.000Z',
      'completedNotes': '已电话约下周到店',
      'assignedTo': 'u-1',
      'createdAt': '2026-09-23T03:00:00.000Z',
    };

void main() {
  group('complete() 契约', () {
    test('发 PATCH /follow-ups/<id> + body {action: "complete"} (不带 notes)',
        () async {
      final adapter = _CapturingAdapter(_completeResponsePayload());
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
        ..httpClientAdapter = adapter;
      final svc = FollowUpService(dio);

      final res = await svc.complete('38');

      // ---- HTTP 形状 ----
      expect(adapter.capturedMethod, 'PATCH');
      expect(adapter.capturedPath, '/follow-ups/38');

      // ---- body: 必须含 action, 不含 status / completedNotes ----
      final body = adapter.capturedBody!;
      expect(body['action'], 'complete');
      expect(body.containsKey('status'), isFalse,
          reason: '老错形状回归 (status 字段已废)');
      expect(body.containsKey('completedNotes'), isFalse,
          reason: '老错形状回归 (completedNotes 字段已废)');

      // ---- 响应能解析成 FollowUpTask, 关键字段都齐 ----
      expect(res.id, '38');
      expect(res.customerId, 'c-123');
      expect(res.status, 'done');
      expect(res.dueAt, DateTime.utc(2026, 9, 24, 9));
      expect(res.reason, 'smoke 契约验证 (可删)');
      expect(res.createdAt, DateTime.utc(2026, 9, 23, 3));
    });

    test('带 notes → body 含 notes; 空串 / null → 不含 notes 键', () async {
      // 1) 正常 notes
      final a1 = _CapturingAdapter(_completeResponsePayload());
      final dio1 = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
        ..httpClientAdapter = a1;
      await FollowUpService(dio1).complete('38', notes: '已微信回访');
      final b1 = a1.capturedBody!;
      expect(b1['action'], 'complete');
      expect(b1['notes'], '已微信回访');

      // 2) 空串 → 不含 notes 键 (避免空串污染后端日志 + 节省字节)
      final a2 = _CapturingAdapter(_completeResponsePayload());
      final dio2 = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
        ..httpClientAdapter = a2;
      await FollowUpService(dio2).complete('38', notes: '');
      expect(a2.capturedBody!.containsKey('notes'), isFalse);

      // 3) null → 不含 notes 键
      final a3 = _CapturingAdapter(_completeResponsePayload());
      final dio3 = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
        ..httpClientAdapter = a3;
      await FollowUpService(dio3).complete('38'); // notes 缺省
      expect(a3.capturedBody!.containsKey('notes'), isFalse);
    });
  });

  group('cancel() 契约', () {
    test('发 PATCH /follow-ups/<id> + body {action: "cancel"} (无其他键)',
        () async {
      final adapter = _CapturingAdapter({
        ..._completeResponsePayload(),
        'status': 'cancelled',
      });
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
        ..httpClientAdapter = adapter;
      final svc = FollowUpService(dio);

      final res = await svc.cancel('38');

      expect(adapter.capturedMethod, 'PATCH');
      expect(adapter.capturedPath, '/follow-ups/38');

      final body = adapter.capturedBody!;
      expect(body, {'action': 'cancel'},
          reason: 'cancel 不应传 notes / status / completedNotes');
      expect(res.status, 'cancelled');
    });
  });
}