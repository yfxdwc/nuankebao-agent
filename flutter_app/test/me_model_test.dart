// 「我的」页模型单测 (GET /api/me + /api/app-version 的解析)
// 关注点: 后端少字段 / 空态 / 老客户端 不能崩, 也不能显示错数字
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/me.dart';

void main() {
  group('MeProfile.fromJson', () {
    test('完整响应 → 各块都解析出来', () {
      final p = MeProfile.fromJson({
        'user': {
          'id': '1',
          'name': '张三',
          'role': 'sales',
          'roleLabel': '销售员',
          'isActive': true,
          'createdAt': '2026-09-16T11:37:31.156Z',
          'hasUserRecord': true,
        },
        'phone': {'full': '13800138000', 'masked': '138****8000'},
        'store': {'id': '3', 'name': '城南店'},
        'franchisee': {
          'id': '75',
          'name': '宋一鸣',
          'phone': {'full': '13900000175', 'masked': '139****0175'},
          'isActive': true,
          'notes': 'A 线负责人',
          'joinedAt': '2026-09-16T11:37:26.315Z',
          'placement': {
            'side': 'left',
            'sideLabel': 'A 线 (左)',
            'depth': 1,
            'depthLabel': '第 1 层',
            'path': 'L.',
          },
          'referrer': {
            'id': '70',
            'name': '王总',
            'phone': {'full': '13700000070', 'masked': '137****0070'},
          },
          'downline': {'total': 2, 'left': 1, 'right': 1, 'unknown': 0},
        },
        'stats': {
          'customerCount': 47,
          'thisMonthVisits': 13,
          'pendingFollowUps': 6,
          'totalInteractions': 2,
          'newCustomersThisMonth': 47,
        },
        'dev': {'authSkipped': false, 'sessionUserId': '1'},
      });

      expect(p.displayName, '宋一鸣'); // 加盟名优先
      expect(p.accountAlias, '张三'); // 跟账号名不一样 → 补一行
      expect(p.isFranchisee, isTrue);
      expect(p.phone!.display, '138****8000');
      expect(p.store!.name, '城南店');
      expect(p.franchisee!.placement!.depthLabel, '第 1 层');
      expect(p.franchisee!.placement!.pathLabel, 'A'); // 'L.' → 'A'
      expect(p.franchisee!.referrer!.name, '王总');
      expect(p.franchisee!.downline.total, 2);
      expect(p.stats!.customerCount, 47);
      expect(p.stats!.newCustomersThisMonth, 47);
      expect(p.authSkipped, isFalse);
    });

    test('未加盟 (franchisee=null / id=0) → 用账号名, 不报错', () {
      final p = MeProfile.fromJson({
        'user': {'id': '9', 'name': '李四', 'roleLabel': '店长'},
        'phone': null,
        'franchisee': null,
        'stats': null,
      });
      expect(p.isFranchisee, isFalse);
      expect(p.displayName, '李四');
      expect(p.accountAlias, isNull);
      expect(p.stats, isNull);

      // 后端对「未加盟」给的是 id=0 的占位树, 也要当未加盟
      final placeholder = MeProfile.fromJson({
        'user': {'id': '9', 'name': '李四'},
        'franchisee': {'id': '0', 'name': '未加盟'},
      });
      expect(placeholder.isFranchisee, isFalse);
    });

    test('字段全缺 (老后端) → 空壳不崩', () {
      final p = MeProfile.fromJson({});
      expect(p.user, isNull);
      expect(p.phone, isNull);
      expect(p.franchisee, isNull);
      expect(p.stats, isNull);
      expect(p.displayName, '我');
    });

    test('dev 空 session (stats=null + authSkipped) → 不崩', () {
      final p = MeProfile.fromJson({
        'user': {'id': '0', 'name': '开发模式', 'hasUserRecord': false},
        'stats': null,
        'dev': {'authSkipped': true, 'sessionUserId': null},
      });
      expect(p.authSkipped, isTrue);
      expect(p.user!.hasUserRecord, isFalse);
      expect(p.stats, isNull);
    });
  });

  group('PhonePair', () {
    test('masked 缺失时退回 full (宁可显示全号, 不显示空白)', () {
      final pair = PhonePair.fromJson({'full': '13800138000', 'masked': ''});
      expect(pair!.display, '13800138000');
    });

    test('全空 → null (UI 直接不渲染这一行)', () {
      expect(PhonePair.fromJson({'full': '', 'masked': ''}), isNull);
      expect(PhonePair.fromJson(null), isNull);
    });
  });

  group('MePlacement.pathLabel', () {
    test('空路径 = 顶级', () {
      const p = MePlacement(
        sideLabel: '顶级 (无上级)',
        depth: 0,
        depthLabel: '顶级',
        path: '',
      );
      expect(p.pathLabel, '(顶级)');
    });

    test('L.R. → A › B (图谱里的叫法)', () {
      const p = MePlacement(
        sideLabel: 'B 线 (右)',
        depth: 2,
        depthLabel: '第 2 层',
        path: 'L.R.',
      );
      expect(p.pathLabel, 'A › B');
    });
  });

  group('AppRelease / ApkArtifact', () {
    test('解析版本 + 安装包', () {
      final r = AppRelease.fromJson({
        'version': '0.2.2',
        'buildNumber': 3,
        'apk': {
          'sizeBytes': 23293494,
          'mtimeLocal': '2026-09-05 05:46:36',
          'md5': 'abc',
          'downloadPath': '/api/apk-download',
          'downloadUrl': 'http://x/api/apk-download',
        },
      });
      expect(r.label, 'v0.2.2 (3)');
      expect(r.apk!.sizeLabel, '22.2 MB');
      expect(r.apk!.downloadUrl, isNotEmpty);
    });

    test('服务器没放包 (apk=null) → 不崩', () {
      final r = AppRelease.fromJson({'version': '0.2.2', 'buildNumber': 3});
      expect(r.apk, isNull);
    });

    test('小文件用 KB', () {
      const a = ApkArtifact(sizeBytes: 512 * 1024);
      expect(a.sizeLabel, '512 KB');
    });
  });

  group('compareVersions', () {
    test('服务器新 → 正数', () {
      expect(compareVersions('0.2.3', '0.2.2'), greaterThan(0));
      expect(compareVersions('0.3', '0.2.9'), greaterThan(0));
      expect(compareVersions('1.0.0', '0.9.9'), greaterThan(0));
    });

    test('一样 / 补齐相等 → 0', () {
      expect(compareVersions('0.2.2', '0.2.2'), 0);
      expect(compareVersions('1.2', '1.2.0'), 0);
    });

    test('本机新 → 负数', () {
      expect(compareVersions('0.2.1', '0.2.2'), lessThan(0));
    });

    test('非数字片段 → 当 0 比, 不抛异常', () {
      expect(compareVersions('dev', '0.0.0'), 0);
      expect(compareVersions('1.0.0-beta', '1.0.0'), 0);
    });
  });
}
