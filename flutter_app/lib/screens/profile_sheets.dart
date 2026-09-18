// ============================================
// 「我的」页弹层 (编辑资料 / 检查更新 / 网络自检)
// ============================================
// 为什么用弹层不用新页面:
//   - 「我的」是高频页, 用户点一下就想改完回来看数字 —— 弹层不丢上下文
//   - 每个弹层内容都很少 (1-3 个控件), 单独开路由反而多一层返回
//
// 异常口径 (全项目一致): 失败一律给大白话提示, 不把 DioException 原文丢给用户

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/http/api_client.dart';
import '../core/models/me.dart';
import '../core/providers/service_providers.dart';
import '../core/theme/app_theme.dart';

// ============================================
// 1. 编辑我的资料 (姓名 + 备注)
// ============================================

Future<bool> showEditMyProfileSheet(
  BuildContext context,
  WidgetRef ref, {
  required MeFranchisee franchisee,
}) async {
  final nameCtrl = TextEditingController(text: franchisee.name);
  final notesCtrl = TextEditingController(text: franchisee.notes ?? '');
  var saving = false;
  var saved = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        Future<void> save() async {
          final name = nameCtrl.text.trim();
          if (name.isEmpty) {
            _toast(ctx, '姓名不能空着');
            return;
          }
          if (name.characters.length > 20) {
            _toast(ctx, '姓名太长了 (最多 20 个字)');
            return;
          }
          setSheetState(() => saving = true);
          try {
            await ref.read(meServiceProvider).updateMyFranchisee(
                  franchisee.id,
                  name: name,
                  notes: notesCtrl.text.trim(),
                );
            // 资料改了 → 让 /api/me 重新拉 (页面上的名字/备注立刻更新)
            ref.invalidate(meProfileProvider);
            saved = true;
            if (ctx.mounted) Navigator.of(ctx).pop();
          } catch (e) {
            setSheetState(() => saving = false);
            _toast(ctx, '没保存成功, 请检查网络后重试');
          }
        }

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '编辑我的资料',
                style: TextStyle(
                  fontSize: AppTheme.fontLg,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '姓名会显示在加盟网络 / 图谱里, 备注只有自己看得到',
                style: TextStyle(
                  fontSize: AppTheme.fontSm,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                style: const TextStyle(fontSize: AppTheme.fontMd),
                maxLength: 20,
                decoration: const InputDecoration(
                  labelText: '姓名 *',
                  hintText: '例: 宋一鸣',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                style: const TextStyle(fontSize: AppTheme.fontMd),
                maxLines: 3,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: '备注 (可不填)',
                  hintText: '例: 负责 A 线团队 / 门店在城南',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: AppTheme.buttonLgHeight,
                child: FilledButton.icon(
                  onPressed: saving ? null : save,
                  icon: saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check, size: 26),
                  label: Text(
                    saving ? '保存中...' : '保存',
                    style: const TextStyle(fontSize: AppTheme.fontMd),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ),
  );

  nameCtrl.dispose();
  notesCtrl.dispose();
  return saved;
}

// ============================================
// 2. 检查更新 (服务器版本 + 安装包 + 下载/二维码)
// ============================================

Future<void> showUpdateSheet(BuildContext context, WidgetRef ref) async {
  ref.invalidate(appReleaseProvider);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => const _UpdateSheetBody(),
  );
}

class _UpdateSheetBody extends ConsumerWidget {
  const _UpdateSheetBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final releaseAsync = ref.watch(appReleaseProvider);
    final infoAsync = ref.watch(_packageInfoProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '版本与更新',
            style: TextStyle(
              fontSize: AppTheme.fontLg,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          // 本机版本
          infoAsync.when(
            loading: () => const _Line(label: '当前版本', value: '读取中...'),
            error: (_, __) => const _Line(label: '当前版本', value: '读取失败'),
            data: (info) => _Line(
              label: '当前版本',
              value: 'v${info.version} (${info.buildNumber})',
            ),
          ),
          // 服务器版本
          releaseAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                const Text(
                  '没拿到服务器版本信息 (网络或服务器暂时不可用)',
                  style: TextStyle(
                    fontSize: AppTheme.fontSm,
                    color: AppTheme.danger,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(appReleaseProvider),
                  icon: const Icon(Icons.refresh, size: 22),
                  label: const Text('重试', style: TextStyle(fontSize: AppTheme.fontMd)),
                ),
              ],
            ),
            data: (release) {
              final hasNewer = _isNewerThanInstalled(release, infoAsync.valueOrNull);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Line(
                    label: '服务器版本',
                    value: release.label.isEmpty ? '未知' : release.label,
                    highlight: hasNewer,
                  ),
                  if (release.apk != null) ...[
                    _Line(label: '安装包时间', value: release.apk!.mtimeLocal),
                    _Line(label: '安装包大小', value: release.apk!.sizeLabel),
                  ],
                  if (hasNewer) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '服务器上的版本比您手机里的新, 可以下载更新',
                        style: TextStyle(
                          fontSize: AppTheme.fontSm,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                  if (release.apk == null) ...[
                    const SizedBox(height: 8),
                    const Text(
                      '服务器上还没有可下载的安装包 (部署时把 APK 放到 flutter_app/build 或 public/downloads 即可)',
                      style: TextStyle(
                        fontSize: AppTheme.fontSm,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: AppTheme.buttonLgHeight,
                      child: FilledButton.icon(
                        onPressed: () => _openDownload(release.apk!.downloadUrl),
                        icon: const Icon(Icons.download, size: 26),
                        label: const Text(
                          '下载 / 更新安装包',
                          style: TextStyle(fontSize: AppTheme.fontMd),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: release.apk!.downloadUrl),
                              );
                              if (context.mounted) {
                                _toast(context, '下载链接已复制');
                              }
                            },
                            icon: const Icon(Icons.link, size: 22),
                            label: const Text(
                              '复制链接',
                              style: TextStyle(fontSize: AppTheme.fontSm),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (dctx) => AlertDialog(
                                title: const Text('让同事扫码安装'),
                                content: SizedBox(
                                  width: 260,
                                  height: 260,
                                  child: _QrImage(url: release.apk!.downloadUrl),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(dctx).pop(),
                                    child: const Text('关闭',
                                        style: TextStyle(fontSize: AppTheme.fontMd)),
                                  ),
                                ],
                              ),
                            ),
                            icon: const Icon(Icons.qr_code_2, size: 22),
                            label: const Text(
                              '扫码安装',
                              style: TextStyle(fontSize: AppTheme.fontSm),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '提示: 下载后点安装包按提示覆盖安装即可, 数据不会丢',
                      style: TextStyle(
                        fontSize: AppTheme.fontXs,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 服务器版本是否比本机新 (本机版本读不出来时不乱提示)
bool _isNewerThanInstalled(AppRelease release, PackageInfo? info) {
  if (info == null || release.version.isEmpty) return false;
  return compareVersions(release.version, info.version) > 0;
}

/// 本机 App 版本 (package_info_plus: Android 读 versionName, web 读 version.json)
final _packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

/// 服务器生成的下载二维码 (需要登录态 → 用 dio 带 cookie 取字节)
class _QrImage extends ConsumerWidget {
  final String url;
  const _QrImage({required this.url});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dio = ref.watch(dioProvider);
    return FutureBuilder<Uint8List>(
      future: dio
          .get<List<int>>(
            '/apk-qr?url=${Uri.encodeComponent(url)}',
            options: Options(responseType: ResponseType.bytes),
          )
          .then((r) => Uint8List.fromList(r.data ?? const [])),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final bytes = snap.data;
        if (snap.hasError || bytes == null || bytes.isEmpty) {
          return const Center(
            child: Text(
              '二维码生成失败\n可以先用「复制链接」发给同事',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppTheme.fontSm),
            ),
          );
        }
        return Image.memory(bytes, fit: BoxFit.contain);
      },
    );
  }
}

Future<void> _openDownload(String url) async {
  if (url.isEmpty) return;
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  // 用系统浏览器打开 → Android 走下载通知, iOS 走 Safari 下载
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

// ============================================
// 3. 网络自检 (服务器 + 登录态诊断)
// ============================================

Future<void> showDiagnosticsSheet(BuildContext context, WidgetRef ref) async {
  ref.invalidate(healthCheckProvider);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => const _DiagnosticsSheetBody(),
  );
}

class _DiagnosticsSheetBody extends ConsumerWidget {
  const _DiagnosticsSheetBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthAsync = ref.watch(healthCheckProvider);
    final profileAsync = ref.watch(meProfileProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '网络自检',
            style: TextStyle(
              fontSize: AppTheme.fontLg,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _Line(label: '服务地址', value: ApiClient.baseUrl),
          profileAsync.when(
            loading: () => const _Line(label: '登录账号', value: '读取中...'),
            error: (_, __) => const _Line(label: '登录账号', value: '读取失败'),
            data: (p) => _Line(
              label: '登录账号',
              value: p.user == null
                  ? '未知'
                  : '#${p.user!.id} ${p.user!.roleLabel}',
            ),
          ),
          healthAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  SizedBox(width: 12),
                  Text('正在连接服务器...',
                      style: TextStyle(fontSize: AppTheme.fontMd)),
                ],
              ),
            ),
            error: (e, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Row(
                  children: const [
                    Icon(Icons.error_outline, color: AppTheme.danger, size: 26),
                    SizedBox(width: 8),
                    Text(
                      '连不上服务器',
                      style: TextStyle(
                        fontSize: AppTheme.fontMd,
                        color: AppTheme.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  '请检查手机网络 / WiFi, 或让管理员确认服务在跑',
                  style: TextStyle(
                    fontSize: AppTheme.fontSm,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            data: (h) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      h.healthy ? Icons.check_circle : Icons.error_outline,
                      color: h.healthy ? AppTheme.primary : AppTheme.danger,
                      size: 26,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      h.healthy ? '服务器正常' : '服务器异常',
                      style: TextStyle(
                        fontSize: AppTheme.fontMd,
                        fontWeight: FontWeight.w600,
                        color: h.healthy ? AppTheme.primaryDark : AppTheme.danger,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '响应 ${h.latencyMs} 毫秒 · 数据库 ${h.db} · 服务端 ${h.serverVersion}',
                  style: const TextStyle(
                    fontSize: AppTheme.fontSm,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => ref.invalidate(healthCheckProvider),
                  icon: const Icon(Icons.refresh, size: 22),
                  label: const Text('重新检测',
                      style: TextStyle(fontSize: AppTheme.fontSm)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final text = await buildDiagnosticText(ref, profileAsync);
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      _toast(context, '诊断信息已复制, 可发给管理员');
                    }
                  },
                  icon: const Icon(Icons.content_copy, size: 22),
                  label: const Text('复制诊断信息',
                      style: TextStyle(fontSize: AppTheme.fontSm)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 给管理员看的诊断文本 (用户复制就能发, 不用教他怎么描述问题)
Future<String> buildDiagnosticText(
  WidgetRef ref,
  AsyncValue<MeProfile> profileAsync,
) async {
  // 先同步取状态, 再 await (await 后再碰 ref = 可能已被销毁)
  final health = ref.read(healthCheckProvider);
  final p = profileAsync.valueOrNull;
  final info = await PackageInfo.fromPlatform();
  final platform = kIsWeb ? 'Web' : defaultTargetPlatform.name;
  final now = DateTime.now();
  final ts = '${now.year}-${_two(now.month)}-${_two(now.day)} '
      '${_two(now.hour)}:${_two(now.minute)}';

  return [
    '【暖客宝 诊断信息】',
    '时间: $ts',
    'App: v${info.version} (${info.buildNumber})',
    '平台: $platform',
    '账号: #${p?.user?.id ?? '?'} ${p?.user?.roleLabel ?? ''}',
    '服务地址: ${ApiClient.baseUrl}',
    '服务器: ${health.when(
      data: (h) => h.healthy
          ? '正常 (${h.latencyMs}ms, db=${h.db}, v${h.serverVersion})'
          : '异常 (${h.status}, db=${h.db})',
      loading: () => '检测中',
      error: (e, _) => '连不上',
    )}',
  ].join('\n');
}

String _two(int n) => n.toString().padLeft(2, '0');

// ============================================
// 小工具
// ============================================

class _Line extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _Line({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: AppTheme.fontSm,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: AppTheme.fontMd,
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                color: highlight ? AppTheme.accent : AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: AppTheme.fontMd)),
    ),
  );
}
