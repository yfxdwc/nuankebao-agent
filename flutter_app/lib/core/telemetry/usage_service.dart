// ============================================
// 使用数据采集服务 (真实用户, release APK)
//
// 主人 2026-09-22 拍: 内部工具**强制开启** (无开关); 原始事件 180 天后删
//
// 设计:
//   1. **只在 release native 采集** (kReleaseMode && !kIsWeb) —— 否则 /app-preview
//      的点击会污染真用户数据。调试时可 --dart-define=NUANKEBAO_TELEMETRY=1 强制开
//   2. 内存队列 + shared_preferences 持久化 (上限 500, 满了丢最旧)
//   3. 刷盘时机: app 进后台 / 60s 定时 / 队列 ≥ 20 (防丢: track 后异步落盘)
//   4. 发送失败保留队列, 下次重试; 永不阻塞 UI / 不影响业务请求
//   5. 幂等: 每条事件带随机 event_id, 服务端唯一索引去重 (重传安全)
//   6. dio 拦截器自动记 api_error / 慢请求 api_latency (≥1s, 只记分桶)
//
// 红线 (CHARTER §4.4.5): props 白名单双端校验; 客户端这里也过滤一遍 (双保险)
// ============================================

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'usage_events.dart';

const String _kQueueKey = 'nb_usage_queue_v1';
const String _kDeviceIdKey = 'nb_usage_device_id_v1';
const String _kFirstLaunchKey = 'nb_usage_first_launch_v1';

const int kUsageQueueMax = 500;
const int kUsageFlushBatch = 50;
const int kUsageFlushThreshold = 20;
const Duration kUsageFlushInterval = Duration(seconds: 60);
const Duration kUsageFlushDebounce = Duration(seconds: 2);
/// 慢请求阈值 (低于这个不记, 免得高频事件淹没数据)
const int kUsageSlowRequestMs = 1000;

/// 发送器 (测试可注入)
typedef UsageSender = Future<bool> Function(Map<String, dynamic> body);

/// 采集开关 (纯函数, 可单测)
///
/// 默认: release native 开; dev / web 关 (不污染真用户数据)
/// 覆盖: --dart-define=NUANKEBAO_TELEMETRY=1 / =0
bool usageTelemetryEnabled({bool? override}) {
  if (override != null) return override;
  const flag = String.fromEnvironment('NUANKEBAO_TELEMETRY');
  if (flag == '1' || flag.toLowerCase() == 'on') return true;
  if (flag == '0' || flag.toLowerCase() == 'off') return false;
  return kReleaseMode && !kIsWeb;
}

/// 路由 → 屏幕模板 (数字段归一为 :id)
///   /customers/123 → /customers/:id
///   /customers/123?tab=x → /customers/:id
String normalizeScreenPath(String location) {
  var path = location;
  final q = path.indexOf('?');
  if (q >= 0) path = path.substring(0, q);
  final h = path.indexOf('#');
  if (h >= 0) path = path.substring(0, h);
  if (!path.startsWith('/')) return '/';
  final segments = path.split('/');
  final out = segments
      .map((s) => RegExp(r'^\d+$').hasMatch(s) ? ':id' : s)
      .join('/');
  return out.isEmpty ? '/' : out;
}

class UsageService with WidgetsBindingObserver {
  final SharedPreferences _prefs;
  final bool enabled;
  final UsageSender? _injectedSender;
  final DateTime Function() _clock;
  final Random _random = Random.secure();

  UsageService({
    required SharedPreferences prefs,
    bool? enabled,
    UsageSender? sender,
    DateTime Function()? clock,
  })  : _prefs = prefs,
        enabled = usageTelemetryEnabled(override: enabled),
        _injectedSender = sender,
        _clock = clock ?? DateTime.now;

  final List<Map<String, dynamic>> _queue = [];
  Dio? _dio;
  Timer? _timer;
  Timer? _debounce;
  bool _started = false;
  bool _flushing = false;
  int _counter = 0;
  int dropped = 0;
  String? _deviceId;
  String? _appVersion;
  String? _platform;

  @visibleForTesting
  int get queueLength => _queue.length;

  // ==========================================
  // 启动 / 停止
  // ==========================================

  Future<void> start(Dio dio) async {
    if (!enabled || _started) return;
    _started = true;
    _dio = dio;

    _loadQueue();
    await _loadDeviceProfile();

    WidgetsBinding.instance.addObserver(this);
    _attachDio(dio);
    _installErrorHandlers();

    final firstLaunch = !(_prefs.getBool(_kFirstLaunchKey) ?? false);
    if (firstLaunch) {
      await _prefs.setBool(_kFirstLaunchKey, true);
    }
    track('app_open', props: {'first': firstLaunch});

    _timer = Timer.periodic(kUsageFlushInterval, (_) => unawaited(flush()));
    unawaited(flush());
  }

  Future<void> stop() async {
    if (!enabled) return;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _debounce?.cancel();
    await _persist();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!enabled) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      track('app_pause');
      unawaited(flush());
    } else if (state == AppLifecycleState.resumed) {
      track('app_resume');
    }
  }

  // ==========================================
  // 上报入口
  // ==========================================

  /// 记一条事件 (sync, 不阻塞 UI)
  void track(
    String name, {
    String? screen,
    String? entityType,
    String? entityId,
    bool? success,
    String? errorCode,
    int? durationMs,
    Map<String, dynamic>? props,
  }) {
    if (!enabled) return;
    final spec = kUsageEvents[name];
    if (spec == null) {
      assert(false, '用量事件词表没有 "$name" (先加 src/lib/usage/catalog.ts)');
      return;
    }

    final safeProps = _sanitizeProps(spec.props, props);
    final event = <String, dynamic>{
      'id': _newId('e'),
      'name': name,
      'ts': _clock().toUtc().toIso8601String(),
      'sessionId': _sessionId,
      if (screen != null) 'screen': screen,
      if (entityType != null && entityId != null) 'entityType': entityType,
      if (entityType != null && entityId != null) 'entityId': entityId,
      if (success != null) 'success': success,
      if (errorCode != null && RegExp(r'^[A-Za-z0-9_.-]{1,64}$').hasMatch(errorCode))
        'errorCode': errorCode,
      if (durationMs != null) 'durationMs': durationMs,
      if (safeProps != null) 'props': safeProps,
    };

    if (_queue.length >= kUsageQueueMax) {
      _queue.removeAt(0);
      dropped += 1;
    }
    _queue.add(event);
    unawaited(_persist());

    if (_queue.length >= kUsageFlushThreshold) {
      _debounce?.cancel();
      _debounce = Timer(kUsageFlushDebounce, () => unawaited(flush()));
    }
  }

  /// 记一次屏幕访问 (路由 observer 调用)
  void screenView(String location) {
    if (!enabled) return;
    track('screen_view', screen: normalizeScreenPath(location));
  }

  // ==========================================
  // 刷盘
  // ==========================================

  Future<void> flush() async {
    if (!enabled || _flushing || _queue.isEmpty) return;
    _flushing = true;
    try {
      while (_queue.isNotEmpty) {
        final batch = _queue.take(kUsageFlushBatch).toList();
        final ok = await _send(batch);
        if (!ok) break;
        _queue.removeRange(0, batch.length);
        await _persist();
        if (batch.length < kUsageFlushBatch) break;
      }
    } catch (_) {
      // 静默: 保留队列, 下次定时器再试 (采集不能影响业务)
    } finally {
      _flushing = false;
    }
  }

  Future<bool> _send(List<Map<String, dynamic>> events) async {
    final body = <String, dynamic>{
      'device': _devicePayload(),
      'events': events,
    };
    final injected = _injectedSender;
    if (injected != null) return injected(body);
    final dio = _dio;
    if (dio == null) return false;
    try {
      final res = await dio.post(
        '/usage/events',
        data: body,
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ==========================================
  // dio 拦截器: API 失败 / 慢请求
  // ==========================================

  void _attachDio(Dio dio) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.extra['nb_usage_t0'] = _clock().millisecondsSinceEpoch;
          handler.next(options);
        },
        onResponse: (response, handler) {
          final t0 = response.requestOptions.extra['nb_usage_t0'];
          if (t0 is int) {
            final ms = _clock().millisecondsSinceEpoch - t0;
            if (ms >= kUsageSlowRequestMs) {
              track(
                'api_latency',
                props: {
                  'path': _normalizePath(response.requestOptions.path),
                  'bucketMs': _bucket(ms),
                },
              );
            }
          }
          handler.next(response);
        },
        onError: (err, handler) {
          final status = err.response?.statusCode;
          track(
            'api_error',
            errorCode: status != null ? 'http_$status' : 'network',
            props: status != null
                ? {
                    'path': _normalizePath(err.requestOptions.path),
                    'status': status,
                  }
                : null,
          );
          handler.next(err);
        },
      ),
    );
  }

  String _normalizePath(String path) {
    final p = normalizeScreenPath(path);
    return p.length > 64 ? p.substring(0, 64) : p;
  }

  int _bucket(int ms) {
    final bucket = ((ms / 500).ceil()) * 500;
    return bucket > 10000 ? 10000 : bucket;
  }

  void _installErrorHandlers() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      track('ui_error', errorCode: details.exception.runtimeType.toString());
    };
    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      track('ui_error', errorCode: error.runtimeType.toString());
      return previousPlatform?.call(error, stack) ?? false;
    };
  }

  // ==========================================
  // 设备 / 队列 内部
  // ==========================================

  String get _sessionId {
    _sessionIdCache ??= _newId('s');
    return _sessionIdCache!;
  }

  String? _sessionIdCache;

  Map<String, dynamic> _devicePayload() => {
        'deviceId': _deviceId ?? 'unknown-device-000',
        if (_appVersion != null) 'appVersion': _appVersion,
        if (_platform != null) 'platform': _platform,
      };

  Future<void> _loadDeviceProfile() async {
    var deviceId = _prefs.getString(_kDeviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = _newId('d');
      await _prefs.setString(_kDeviceIdKey, deviceId);
    }
    _deviceId = deviceId;

    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = info.version;
    } catch (_) {
      _appVersion = null;
    }

    if (!kIsWeb) {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          _platform = 'android';
          break;
        case TargetPlatform.iOS:
          _platform = 'ios';
          break;
        case TargetPlatform.macOS:
          _platform = 'macos';
          break;
        case TargetPlatform.windows:
          _platform = 'windows';
          break;
        case TargetPlatform.linux:
          _platform = 'linux';
          break;
        case TargetPlatform.fuchsia:
          _platform = 'linux';
          break;
      }
    } else {
      _platform = 'web';
    }
  }

  Map<String, dynamic>? _sanitizeProps(
    List<String> allowed,
    Map<String, dynamic>? raw,
  ) {
    if (raw == null || raw.isEmpty) return null;
    final out = <String, dynamic>{};
    for (final entry in raw.entries) {
      if (!allowed.contains(entry.key)) continue;
      final v = entry.value;
      if (v is bool) {
        out[entry.key] = v;
      } else if (v is num) {
        if (v.isFinite && v.abs() <= 1000000000) out[entry.key] = v;
      } else if (v is String) {
        if (v.length <= 64 &&
            RegExp(r'^[A-Za-z0-9_.:/@-]*$').hasMatch(v) &&
            !RegExp(r'1[3-9]\d{9}').hasMatch(v)) {
          out[entry.key] = v;
        }
      }
    }
    return out.isEmpty ? null : out;
  }

  String _newId(String prefix) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = List.generate(6, (_) => chars[_random.nextInt(chars.length)])
        .join();
    _counter = (_counter + 1) % 100000;
    return '$prefix${_clock().microsecondsSinceEpoch.toRadixString(36)}'
        '-$_counter-$rand';
  }

  void _loadQueue() {
    final raw = _prefs.getStringList(_kQueueKey) ?? const [];
    for (final line in raw) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, dynamic>) _queue.add(decoded);
      } catch (_) {
        // 坏行跳过
      }
    }
    if (_queue.length > kUsageQueueMax) {
      dropped += _queue.length - kUsageQueueMax;
      _queue.removeRange(0, _queue.length - kUsageQueueMax);
    }
  }

  Future<void> _persist() async {
    try {
      await _prefs.setStringList(
        _kQueueKey,
        _queue.map(jsonEncode).toList(),
      );
    } catch (_) {
      // 落盘失败不影响内存队列
    }
  }
}
