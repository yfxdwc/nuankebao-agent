// 用量采集服务单元测试
// 依据: CHARTER §4.4.5 用量红线 + src/lib/usage/catalog.ts 双端契约
//
// 覆盖:
//   - 采集开关 (release native 默认 / dart-define 覆盖 / dev-web 关闭)
//   - 路由归一化 (数字段 → :id, 去 query)
//   - 队列上限 500 (丢最旧 + dropped 计数)
//   - flush 分批 ≤50 / 成功后清空 / 失败保留
//   - props 客户端白名单 (中文/手机号/超长/未知键写不进)
//   - 词表外事件不产生数据

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nuankebao/core/telemetry/usage_events.dart';
import 'package:nuankebao/core/telemetry/usage_service.dart';

Future<UsageService> makeService({
  UsageSender? sender,
  bool enabled = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return UsageService(
    prefs: prefs,
    enabled: enabled,
    sender: sender ?? (body) async => true,
  );
}

void main() {
  group('采集开关', () {
    test('显式 override 优先', () {
      expect(usageTelemetryEnabled(override: true), isTrue);
      expect(usageTelemetryEnabled(override: false), isFalse);
    });

    test('测试环境 (非 release) 默认关闭', () {
      // flutter test 不是 release 构建; 且 dart-define 未设
      expect(usageTelemetryEnabled(), isFalse);
    });
  });

  group('路由归一化', () {
    test('数字段 → :id, 去 query', () {
      expect(normalizeScreenPath('/customers/123'), '/customers/:id');
      expect(normalizeScreenPath('/customers/123?tab=a'), '/customers/:id');
      expect(normalizeScreenPath('/customers'), '/customers');
      expect(normalizeScreenPath('/salons/9/manage'), '/salons/:id/manage');
      expect(normalizeScreenPath('/wellness-records/42/edit'),
          '/wellness-records/:id/edit');
    });

    test('非路径输入回退 /', () {
      expect(normalizeScreenPath('customers'), '/');
    });
  });

  group('队列与 flush', () {
    test('关闭时 track 不产生任何数据', () async {
      final service = await makeService(enabled: false);
      service.track('screen_view', screen: '/customers');
      expect(service.queueLength, 0);
      await service.flush();
    });

    test('flush 成功后队列清空, 且分批 ≤50', () async {
      final batches = <int>[];
      final service = await makeService(
        sender: (body) async {
          batches.add((body['events'] as List).length);
          return true;
        },
      );
      for (var i = 0; i < 120; i++) {
        service.track('screen_view', screen: '/customers');
      }
      expect(service.queueLength, 120);

      await service.flush();
      expect(service.queueLength, 0);
      expect(batches, [50, 50, 20]);
    });

    test('发送失败保留队列 (下次重试)', () async {
      final service = await makeService(sender: (body) async => false);
      service.track('screen_view', screen: '/customers');
      await service.flush();
      expect(service.queueLength, 1);
    });

    test('队列超过 500 丢最旧 + dropped 计数', () async {
      final service = await makeService();
      for (var i = 0; i < 505; i++) {
        service.track('screen_view', screen: '/customers/$i');
      }
      expect(service.queueLength, 500);
      expect(service.dropped, 5);
    });

    test('事件带 id / 词表 category / 时间戳', () async {
      Map<String, dynamic>? captured;
      final service = await makeService(
        sender: (body) async {
          captured = (body['events'] as List).first as Map<String, dynamic>;
          return true;
        },
      );
      service.track('ai_generate_click', props: {'card': AiCard.profile});
      await service.flush();
      expect(captured, isNotNull);
      expect(captured!['name'], 'ai_generate_click');
      expect(RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(captured!['id'] as String),
          isTrue);
      expect(DateTime.tryParse(captured!['ts'] as String), isNotNull);
      expect(captured!['props'], {'card': 'profile'});
    });
  });

  group('props 客户端白名单 (双保险)', () {
    test('未知键 / 中文 / 手机号 / 超长写不进', () async {
      Map<String, dynamic>? captured;
      final service = await makeService(
        sender: (body) async {
          captured = (body['events'] as List).first as Map<String, dynamic>;
          return true;
        },
      );
      service.track('customer_search', props: {
        'keywordLen': 3,
        'keyword': '张三',
        'phone': '13800138000',
        'note': '腰椎间盘突出',
      });
      await service.flush();
      expect(captured!['props'], {'keywordLen': 3});
    });

    test('词表外事件不产生数据 (debug 下断言提醒, release 静默忽略)', () async {
      final service = await makeService();
      // flutter test 跑在 debug: 断言会炸 (提醒双端词表漂移), 队列仍为空
      expect(() => service.track('not_a_real_event'), throwsAssertionError);
      expect(service.queueLength, 0);
    });
  });
}
