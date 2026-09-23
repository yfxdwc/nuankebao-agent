// ============================================
// 「我的」页弹层 (编辑资料 / 检查更新 / 网络自检)
// ============================================
// 为什么用弹层不用新页面:
//   - 「我的」是高频页, 用户点一下就想改完回来看数字 —— 弹层不丢上下文
//   - 每个弹层内容都很少 (1-3 个控件), 单独开路由反而多一层返回
//
// 异常口径 (全项目一致): 失败一律给大白话提示, 不把 DioException 原文丢给用户

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/http/api_client.dart';
import '../core/widgets/empty_state.dart';
import '../core/http/session_token.dart';
import '../core/models/me.dart';
import '../core/services/api.dart' show ManualPayProduct;
import '../core/providers/service_providers.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/user_avatar.dart';

import '../core/theme/tokens.g.dart';
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
            left: AppSpace.s16,
            right: AppSpace.s16,
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
              const SizedBox(height: AppSpace.s4),
              const Text(
                '姓名会显示在加盟网络 / 图谱里, 备注只有自己看得到',
                style: TextStyle(
                  fontSize: AppTheme.fontSm,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpace.s16),
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
              const SizedBox(height: AppSpace.s12),
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
              const SizedBox(height: AppSpace.s16),
              SizedBox(
                width: double.infinity,
                height: AppTheme.buttonLgHeight,
                child: FilledButton.icon(
                  onPressed: saving ? null : save,
                  icon: saving
                      ? const SizedBox(
                          width: AppSpace.s22,
                          height: AppSpace.s22,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check, size: AppSize.iconLg),
                  label: Text(
                    saving ? '保存中...' : '保存',
                    style: const TextStyle(fontSize: AppTheme.fontMd),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.s8),
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
      padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, 16, 24),
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
          const SizedBox(height: AppSpace.s12),
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
              padding: EdgeInsets.symmetric(vertical: AppSpace.s16),
              child: LoadingState(),
            ),
            error: (e, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpace.s8),
                const Text(
                  '没拿到服务器版本信息 (网络或服务器暂时不可用)',
                  style: TextStyle(
                    fontSize: AppTheme.fontSm,
                    color: AppTheme.danger,
                  ),
                ),
                const SizedBox(height: AppSpace.s8),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(appReleaseProvider),
                  icon: const Icon(Icons.refresh, size: AppSize.iconMd),
                  label: const Text('重试',
                      style: TextStyle(fontSize: AppTheme.fontMd)),
                ),
              ],
            ),
            data: (release) {
              final hasNewer =
                  _isNewerThanInstalled(release, infoAsync.valueOrNull);
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
                    const SizedBox(height: AppSpace.s8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpace.s12),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(AppRadius.r12),
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
                    const SizedBox(height: AppSpace.s8),
                    const Text(
                      '服务器上还没有可下载的安装包 (部署时把 APK 放到 flutter_app/build 或 public/downloads 即可)',
                      style: TextStyle(
                        fontSize: AppTheme.fontSm,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: AppSpace.s16),
                    SizedBox(
                      width: double.infinity,
                      height: AppTheme.buttonLgHeight,
                      child: FilledButton.icon(
                        onPressed: () =>
                            _openDownload(release.apk!.downloadUrl),
                        icon: const Icon(Icons.download, size: AppSize.iconLg),
                        label: const Text(
                          '下载 / 更新安装包',
                          style: TextStyle(fontSize: AppTheme.fontMd),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpace.s8),
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
                            icon: const Icon(Icons.link, size: AppSize.iconMd),
                            label: const Text(
                              '复制链接',
                              style: TextStyle(fontSize: AppTheme.fontSm),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpace.s8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (dctx) => AlertDialog(
                                title: const Text('让同事扫码安装'),
                                content: SizedBox(
                                  width: 260,
                                  height: 260,
                                  child:
                                      QrImage(url: release.apk!.downloadUrl),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(dctx).pop(),
                                    child: const Text('关闭',
                                        style: TextStyle(
                                            fontSize: AppTheme.fontMd)),
                                  ),
                                ],
                              ),
                            ),
                            icon: const Icon(Icons.qr_code_2, size: AppSize.iconMd),
                            label: const Text(
                              '扫码安装',
                              style: TextStyle(fontSize: AppTheme.fontSm),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.s8),
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

/// 服务器生成的下载二维码 (公开端点, 用登录态 dio 仅是因为 dioProvider 已带 cookie
/// — 后端 apk-qr 已去登录保护, 这里 dio 不带 cookie 也能用)
///
/// [size] = 渲染正方形边长 (默认 300; "我的" 页面 APK 二维码传 180 更紧凑)
class QrImage extends ConsumerWidget {
  final String url;
  final double size;
  const QrImage({super.key, required this.url, this.size = 300});

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
          return SizedBox(
            width: size,
            height: size,
            child: const LoadingState(),
          );
        }
        final bytes = snap.data;
        if (snap.hasError || bytes == null || bytes.isEmpty) {
          return SizedBox(
            width: size,
            height: size,
            child: const Center(
              child: Text(
                '二维码生成失败\n可以先用「复制链接」发给同事',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppTheme.fontSm),
              ),
            ),
          );
        }
        return Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.contain,
        );
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
      padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, 16, 24),
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
          const SizedBox(height: AppSpace.s12),
          _Line(label: '服务地址', value: ApiClient.baseUrl),
          // 安装包信息: 升级/发版前对照签名 (签名变了 = 覆盖安装会失败, 必须卸载 = 掉登录)
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snap) => _Line(
              label: '安装包',
              value: snap.hasData
                  ? installInfoLine(
                      packageName: snap.data!.packageName,
                      version: snap.data!.version,
                      buildNumber: snap.data!.buildNumber,
                      buildSignature: snap.data!.buildSignature,
                    )
                  : '读取中...',
            ),
          ),
          // 登录态 (主人 2026-09-20: 想看"会不会又要重新登录")
          FutureBuilder<String?>(
            future: ApiClient.sessionToken(),
            builder: (context, snap) => _Line(
              label: '登录状态',
              value: snap.connectionState != ConnectionState.done
                  ? '检查中...'
                  : (snap.data == null || snap.data!.isEmpty
                      ? '本地没有登录凭证 (需要重新登录)'
                      : sessionExpiryLabel(snap.data)),
            ),
          ),
          profileAsync.when(
            loading: () => const _Line(label: '登录账号', value: '读取中...'),
            error: (_, __) => const _Line(label: '登录账号', value: '读取失败'),
            data: (p) => _Line(
              label: '登录账号',
              value:
                  p.user == null ? '未知' : '#${p.user!.id} ${p.user!.roleLabel}',
            ),
          ),
          healthAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpace.s12),
              child: Row(
                children: [
                  SizedBox(
                    width: AppSpace.s22,
                    height: AppSpace.s22,
                    child: LoadingState(size: 24),
                  ),
                  SizedBox(width: AppSpace.s12),
                  Text('正在连接服务器...',
                      style: TextStyle(fontSize: AppTheme.fontMd)),
                ],
              ),
            ),
            error: (e, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpace.s8),
                Row(
                  children: const [
                    Icon(Icons.error_outline, color: AppTheme.danger, size: AppSize.iconLg),
                    SizedBox(width: AppSpace.s8),
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
                const SizedBox(height: AppSpace.s4),
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
                const SizedBox(height: AppSpace.s8),
                Row(
                  children: [
                    Icon(
                      h.healthy ? Icons.check_circle : Icons.error_outline,
                      color: h.healthy ? AppTheme.primary : AppTheme.danger,
                      size: AppSize.iconLg,
                    ),
                    const SizedBox(width: AppSpace.s8),
                    Text(
                      h.healthy ? '服务器正常' : '服务器异常',
                      style: TextStyle(
                        fontSize: AppTheme.fontMd,
                        fontWeight: FontWeight.w600,
                        color:
                            h.healthy ? AppTheme.primaryDark : AppTheme.danger,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.s4),
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
          const SizedBox(height: AppSpace.s16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => ref.invalidate(healthCheckProvider),
                  icon: const Icon(Icons.refresh, size: AppSize.iconMd),
                  label: const Text('重新检测',
                      style: TextStyle(fontSize: AppTheme.fontSm)),
                ),
              ),
              const SizedBox(width: AppSpace.s8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final text = await buildDiagnosticText(ref, profileAsync);
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      _toast(context, '诊断信息已复制, 可发给管理员');
                    }
                  },
                  icon: const Icon(Icons.content_copy, size: AppSize.iconMd),
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
    '安装包: ${installInfoLine(
      packageName: info.packageName,
      version: info.version,
      buildNumber: info.buildNumber,
      buildSignature: info.buildSignature,
    )}',
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
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: AppSpace.s84,
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

// ============================================
// 4. 换头像 (拍照 / 相册 / 内置候选 / 恢复默认)
// ============================================
// 主人要 (2026-09-18): 「用户头像要能够自定义（上传头像），增加几个候选头像
// 供不希望用真人头像的用户选择」
//
// 存储策略 (为什么这么定):
//   - 上传的照片: 走现成的 POST /api/photos → 服务器 public/uploads/xxx.jpg
//     (不新增存储设施, 复用养生记录照片那条链路, 有体积/格式/限流校验)
//   - 头像值落到 user.avatar_url (自建服务器上), 不是"只存这台手机":
//     换手机/重装 App 头像还在, 同事/后台看到的也是同一个
//   - 内置候选只存 'preset:x' 一个短字符串, 图由客户端本地画 → 不占服务器、不跑流量
//
// 安全边界 (服务端也有一份, 客户端只是提前拦):
//   - 只允许本站上传路径 /uploads/xxx.(jpg|png|webp) 与 preset:x, 拒外链
//   - 上传前本地压到 ≤512px / ≤3MB, 网络差也能传上去

/// [onApply] 可选: 自定义"保存头像"的动作 (默认 = 改「我的」头像)。
///   客户详情页传自己的实现 (PATCH /api/customers/:id), 复用同一套 UI/上传/白名单。
///   [title]/[subtitle] 可选: 换个说法 (客户页说"客户的头像", 我的页说"你的头像")
Future<bool> showAvatarPickerSheet(
  BuildContext context,
  WidgetRef ref, {
  required String? currentAvatarUrl,
  required String name,
  Future<void> Function(String? value)? onApply,
  String title = '换个头像',
  String subtitle = '用自己的照片, 或者挑一个现成的 (花草茶禅, 不想露脸就用这些)',
}) async {
  var changed = false;
  var busy = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        Future<void> apply(String? value, String okMsg) async {
          if (busy) return;
          setSheetState(() => busy = true);
          try {
            if (onApply != null) {
              await onApply(value);
            } else {
              await ref.read(meServiceProvider).updateAvatar(value);
              ref.invalidate(meProfileProvider);
            }
            changed = true;
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
              _toast(ctx, okMsg);
            }
          } catch (e) {
            setSheetState(() => busy = false);
            _toast(ctx, '没换上, 请检查网络后重试');
          }
        }

        Future<void> pickAndUpload(ImageSource source) async {
          if (busy) return;
          try {
            final file = await ImagePicker().pickImage(
              source: source,
              maxWidth: 512,
              maxHeight: 512,
              imageQuality: 85,
            );
            if (file == null) return; // 用户取消
            final bytes = await file.readAsBytes();
            if (bytes.isEmpty) {
              _toast(ctx, '这张照片读不出来, 换一张试试');
              return;
            }
            if (bytes.length > 3 * 1024 * 1024) {
              _toast(ctx, '照片太大了 (超过 3MB), 换一张小点的');
              return;
            }
            setSheetState(() => busy = true);
            final url = await ref.read(photoServiceProvider).upload(
                  base64Encode(bytes),
                  mimeType: _sniffImageMime(bytes),
                  purpose: 'avatar', // 个人头像免费 (ADR-0012), 不受会员限制
                );
            if (onApply != null) {
              await onApply(url);
            } else {
              await ref.read(meServiceProvider).updateAvatar(url);
              ref.invalidate(meProfileProvider);
            }
            changed = true;
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
              _toast(ctx, '头像已换好');
            }
          } catch (e) {
            setSheetState(() => busy = false);
            _toast(ctx, '上传失败, 请检查网络后重试');
          }
        }

        return Padding(
          padding: EdgeInsets.only(
            left: AppSpace.s16,
            right: AppSpace.s16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: AppTheme.fontLg,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpace.s4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: AppTheme.fontSm,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpace.s16),

              // 当前头像 + 拍照/相册
              Row(
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      UserAvatar(
                        avatarUrl: currentAvatarUrl,
                        name: name,
                        size: AppSize.avatarLg,
                      ),
                      if (busy)
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: SizedBox(
                                width: AppSpace.s26,
                                height: AppSpace.s26,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: AppSpace.s16),
                  Expanded(
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: AppTheme.buttonMinHeight,
                          child: FilledButton.icon(
                            onPressed: busy
                                ? null
                                : () => pickAndUpload(ImageSource.camera),
                            icon: const Icon(Icons.photo_camera, size: AppSize.iconLg),
                            label: const Text('拍一张',
                                style: TextStyle(fontSize: AppTheme.fontMd)),
                          ),
                        ),
                        const SizedBox(height: AppSpace.s8),
                        SizedBox(
                          width: double.infinity,
                          height: AppTheme.buttonMinHeight,
                          child: OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () => pickAndUpload(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library, size: AppSize.iconLg),
                            label: const Text('从相册选',
                                style: TextStyle(fontSize: AppTheme.fontMd)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.s20),

              const Text(
                '或者挑一个现成的',
                style: TextStyle(
                  fontSize: AppTheme.fontMd,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpace.s12),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: kAvatarPresets.map((p) {
                  final selected = currentAvatarUrl == 'preset:${p.id}';
                  return Semantics(
                    label: '候选头像 ${p.label}',
                    button: true,
                    child: InkWell(
                      onTap: busy
                          ? null
                          : () => apply('preset:${p.id}', '头像已换成「${p.label}」'),
                      borderRadius: BorderRadius.circular(AppRadius.r40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected
                                    ? AppTheme.primary
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            padding: const EdgeInsets.all(AppSpace.s2),
                            child: UserAvatar(
                              avatarUrl: 'preset:${p.id}',
                              name: name,
                              size: AppSize.fabSize,
                              showLoadingIndicator: false,
                            ),
                          ),
                          const SizedBox(height: AppSpace.s4),
                          Text(
                            p.label,
                            style: TextStyle(
                              fontSize: AppTheme.fontXs,
                              color: selected
                                  ? AppTheme.primaryDark
                                  : AppTheme.textSecondary,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpace.s16),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.restart_alt, size: AppSize.iconLg),
                title: const Text('恢复默认头像',
                    style: TextStyle(fontSize: AppTheme.fontMd)),
                subtitle: const Text('用姓名第一个字当头像',
                    style: TextStyle(fontSize: AppTheme.fontXs)),
                onTap: busy ? null : () => apply(null, '已恢复默认头像'),
              ),
            ],
          ),
        );
      },
    ),
  );

  return changed;
}

// ============================================
// 修改密码 (P2 账号密码登录, 2026-09-19)
// ============================================

Future<void> showChangePasswordSheet(
    BuildContext context, WidgetRef ref) async {
  final oldCtrl = TextEditingController();
  final newCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();
  var submitting = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        Future<void> submit() async {
          final oldPwd = oldCtrl.text;
          final newPwd = newCtrl.text;
          final confirm = confirmCtrl.text;

          if (oldPwd.isEmpty) {
            _toast(ctx, '请输入当前密码');
            return;
          }
          if (newPwd.length < 8 ||
              !RegExp(r'[A-Za-z]').hasMatch(newPwd) ||
              !RegExp(r'\d').hasMatch(newPwd)) {
            _toast(ctx, '新密码至少 8 位, 需同时包含字母和数字');
            return;
          }
          if (newPwd != confirm) {
            _toast(ctx, '两次输入的新密码不一致');
            return;
          }

          setSheetState(() => submitting = true);
          try {
            await ref.read(authServiceProvider).changePassword(
                  oldPassword: oldPwd,
                  newPassword: newPwd,
                );
            if (ctx.mounted) Navigator.pop(ctx);
            _toast(context, '密码已修改, 下次登录用新密码');
          } catch (e) {
            var msg = '修改失败, 请稍后再试';
            if (e is DioException) {
              final data = e.response?.data;
              if (data is Map && data['error'] is String) {
                msg = data['error'] as String;
              } else if (e.response?.statusCode == 401) {
                msg = '当前密码不正确';
              }
            }
            if (ctx.mounted) _toast(ctx, msg);
          } finally {
            if (ctx.mounted) setSheetState(() => submitting = false);
          }
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '修改密码',
                style: TextStyle(
                  fontSize: AppTheme.fontLg,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpace.s4),
              const Text(
                '至少 8 位, 需同时包含字母和数字',
                style: TextStyle(
                  fontSize: AppTheme.fontSm,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpace.s16),
              TextField(
                controller: oldCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '当前密码',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: AppSpace.s12),
              TextField(
                controller: newCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '新密码',
                  prefixIcon: Icon(Icons.password_outlined),
                ),
              ),
              const SizedBox(height: AppSpace.s12),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '确认新密码',
                  prefixIcon: Icon(Icons.check_circle_outline),
                ),
              ),
              const SizedBox(height: AppSpace.s20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: submitting ? null : submit,
                  child: submitting
                      ? const SizedBox(
                          width: AppSpace.s20,
                          height: AppSpace.s20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('确认修改'),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  oldCtrl.dispose();
  newCtrl.dispose();
  confirmCtrl.dispose();
}

/// 修改登录手机号 (自助改号 — 替代"换号要找管理员")
/// 流程: 当前密码验证身份 + 新手机号 + 二次输入确认
///   校验同注册 (/^1[3-9]\d{9}$/), 改完提示"下次登录用新手机号"
///   改完自动 invalidate meProfileProvider → 「我的」页头部立刻显示新号
/// 不做的事:
///   - 不强制重新登录 (跟改密码一致; session.user.phone 是 jwt 首次签发快照, 不刷新)
///   - 不同号 SMS 验证码 (项目没接真短信网关, 旧密码即当前身份的最强证据)
Future<void> showChangePhoneSheet(
    BuildContext context, WidgetRef ref) async {
  final pwdCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();
  var submitting = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        Future<void> submit() async {
          final pwd = pwdCtrl.text;
          final newPhone = phoneCtrl.text.trim();
          final confirm = confirmCtrl.text.trim();

          if (pwd.isEmpty) {
            _toast(ctx, '请输入当前密码');
            return;
          }
          if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(newPhone)) {
            _toast(ctx, '新手机号格式不对 (11 位, 1[3-9] 开头)');
            return;
          }
          if (newPhone != confirm) {
            _toast(ctx, '两次输入的新手机号不一致');
            return;
          }

          setSheetState(() => submitting = true);
          try {
            await ref.read(authServiceProvider).changePhone(
                  password: pwd,
                  newPhone: newPhone,
                );
            // 改完刷新「我的」资料 (新号立刻显示在头部)
            ref.invalidate(meProfileProvider);
            if (ctx.mounted) Navigator.pop(ctx);
            _toast(context, '手机号已修改, 下次登录用新手机号');
          } catch (e) {
            var msg = '修改失败, 请稍后再试';
            if (e is DioException) {
              final data = e.response?.data;
              if (data is Map && data['error'] is String) {
                msg = data['error'] as String;
              } else if (e.response?.statusCode == 401) {
                msg = '当前密码不正确';
              } else if (e.response?.statusCode == 409) {
                msg = data is Map && data['error'] is String
                    ? data['error'] as String
                    : '新手机号已被其他账号使用';
              }
            }
            if (ctx.mounted) _toast(ctx, msg);
          } finally {
            if (ctx.mounted) setSheetState(() => submitting = false);
          }
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '修改登录手机号',
                style: TextStyle(
                  fontSize: AppTheme.fontLg,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpace.s4),
              const Text(
                '改完下次登录请用新手机号; 同手机号的客户档案会一起改',
                style: TextStyle(
                  fontSize: AppTheme.fontSm,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpace.s16),
              TextField(
                controller: pwdCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '当前密码',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: AppSpace.s12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: '新手机号',
                  prefixIcon: Icon(Icons.phone_iphone),
                  hintText: '11 位, 1[3-9] 开头',
                ),
              ),
              const SizedBox(height: AppSpace.s12),
              TextField(
                controller: confirmCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: '确认新手机号',
                  prefixIcon: Icon(Icons.check_circle_outline),
                ),
              ),
              const SizedBox(height: AppSpace.s20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: submitting ? null : submit,
                  child: submitting
                      ? const SizedBox(
                          width: AppSpace.s20,
                          height: AppSpace.s20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('确认修改'),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  pwdCtrl.dispose();
  phoneCtrl.dispose();
  confirmCtrl.dispose();
}

/// 从字节头判图片类型 (image_picker 在 web 上不改后缀, 只信后缀会传错 mime)
String _sniffImageMime(List<int> bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 && // R
      bytes[1] == 0x49 && // I
      bytes[2] == 0x46 && // F
      bytes[3] == 0x46 && // F
      bytes[8] == 0x57 && // W
      bytes[9] == 0x45 && // E
      bytes[10] == 0x42 && // B
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  return 'image/jpeg';
}

// ============================================
// 5. 开通会员 (内测人工通道: 个人微信收款码 + 管理员核销)
// ============================================
// 主人 2026-09-19: 「当前内测阶段，暂时用我个人的微信收款码实现」
//
// 流程 (App 内闭环, 不用碰服务器文件):
//   1. 弹层显示收款码 (管理员上传的 /uploads/xxx.png, 或静态兜底 /payment/wechat-qr.png)
//   2. 用户扫码付款 → 回来填备注 (手机号后 4 位) ± 传付款截图 → 点「我已支付」
//   3. 提交后状态 = 待确认; 管理员在「管理员工具 → 待审付款」里通过 → 会员立刻生效
//
// 为什么付款截图用 purpose=payment_proof: 付钱的人**还不是会员**, 不能拿会员功能拦他

Future<void> showMembershipPurchaseSheet(
  BuildContext context,
  WidgetRef ref, {
  required bool isMember,
}) async {
  ref.invalidate(manualPayInfoProvider);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _PurchaseSheetBody(isMember: isMember),
  );
}

class _PurchaseSheetBody extends ConsumerStatefulWidget {
  final bool isMember;
  const _PurchaseSheetBody({required this.isMember});

  @override
  ConsumerState<_PurchaseSheetBody> createState() => _PurchaseSheetBodyState();
}

class _PurchaseSheetBodyState extends ConsumerState<_PurchaseSheetBody> {
  String? _planCode;
  final _noteCtrl = TextEditingController();
  String? _proofUrl;
  bool _busy = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickProof() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 80,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 3 * 1024 * 1024) {
        if (mounted) _toast(context, '截图太大了 (超过 3MB), 换一张小的');
        return;
      }
      setState(() => _busy = true);
      final url = await ref.read(photoServiceProvider).upload(
            base64Encode(bytes),
            mimeType: _sniffImageMime(bytes),
            purpose: 'payment_proof', // 付款凭证免费上传 (还没会员)
          );
      if (!mounted) return;
      setState(() {
        _proofUrl = url;
        _busy = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _toast(context, '截图上传失败, 也可以不传直接提交');
      }
    }
  }

  Future<void> _submit(ManualPayProduct product) async {
    setState(() => _busy = true);
    final r = await ref.read(billingServiceProvider).submitManualPayment(
          planCode: product.planCode,
          payerNote: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          proofUrl: _proofUrl,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      ref.invalidate(manualPayInfoProvider);
      ref.invalidate(meProfileProvider);
      Navigator.of(context).pop();
      _toast(context, r.message);
    } else {
      _toast(context, r.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final infoAsync = ref.watch(manualPayInfoProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.s20, 0, 20, 28),
      child: infoAsync.when(
        loading: () => const SizedBox(
          height: 200,
          child: LoadingState(),
        ),
        error: (e, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpace.s20),
            const Text('没拿到收款信息, 请检查网络后重试',
                style: TextStyle(fontSize: AppTheme.fontMd)),
            const SizedBox(height: AppSpace.s16),
            OutlinedButton(
              onPressed: () => ref.invalidate(manualPayInfoProvider),
              child: const Text('重试', style: TextStyle(fontSize: AppTheme.fontMd)),
            ),
            const SizedBox(height: AppSpace.s8),
          ],
        ),
        data: (info) {
          final products = info.products;
          final selected = _planCode ?? (products.isNotEmpty ? products.first.planCode : null);
          final latest = info.latestRequest;

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isMember ? '续费会员' : '开通会员',
                  style: const TextStyle(
                    fontSize: AppTheme.fontLg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpace.s4),
                Text(
                  '内测期间用管理员微信收款, 付款后点「我已支付」, 管理员核对到账立刻开通',
                  style: const TextStyle(fontSize: AppTheme.fontSm, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: AppSpace.s16),

                // 待确认提示 (最近一条 pending)
                if (latest != null && latest.status == 'pending') ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpace.s12),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(AppRadius.r12),
                    ),
                    child: const Text(
                      '你已经提交过付款申请, 等管理员确认 (通常几分钟内)',
                      style: TextStyle(fontSize: AppTheme.fontSm),
                    ),
                  ),
                  const SizedBox(height: AppSpace.s12),
                ] else if (latest != null && latest.status == 'rejected') ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpace.s12),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(AppRadius.r12),
                    ),
                    child: Text(
                      '上次申请未通过${latest.rejectReason == null ? '' : ': ${latest.rejectReason}'}\n可以核对后重新提交',
                      style: const TextStyle(fontSize: AppTheme.fontSm),
                    ),
                  ),
                  const SizedBox(height: AppSpace.s12),
                ],

                // 金额选择
                const Text('选一个', style: TextStyle(fontSize: AppTheme.fontMd, fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpace.s8),
                Wrap(
                  spacing: 10,
                  children: products
                      .map((p) => ChoiceChip(
                            label: Text('${p.label} ${p.amountLabel}',
                                style: const TextStyle(fontSize: AppTheme.fontSm)),
                            selected: selected == p.planCode,
                            onSelected: (_) => setState(() => _planCode = p.planCode),
                          ))
                      .toList(),
                ),
                const SizedBox(height: AppSpace.s16),

                // 收款码
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.primaryLight, width: AppSpace.s2),
                          borderRadius: BorderRadius.circular(AppRadius.r12),
                          color: Colors.white,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _QrImageLarge(url: info.qrUrl),
                      ),
                      const SizedBox(height: AppSpace.s8),
                      Text(
                        '收款人: ${info.payeeName}',
                        style: const TextStyle(
                          fontSize: AppTheme.fontMd,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      // 只有"真的取不到码"才提示 (静态兜底文件存在时不再误报)
                      if (!info.qrAvailable)
                        const Padding(
                          padding: EdgeInsets.only(top: AppSpace.s6),
                          child: Text(
                            '管理员还没设置收款码 (设置后这里会显示二维码)',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.danger),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.s16),

                // 备注 + 截图
                TextField(
                  controller: _noteCtrl,
                  style: const TextStyle(fontSize: AppTheme.fontMd),
                  decoration: InputDecoration(
                    labelText: '付款备注',
                    hintText: info.noteHint.isEmpty ? '微信昵称 / 手机号后 4 位' : info.noteHint,
                  ),
                ),
                const SizedBox(height: AppSpace.s8),
                // 全宽 = 用 SizedBox 而不是 Row: 主题里 OutlinedButton 的
                //   minimumSize 是 Size(double.infinity, 56) (大按钮语义), 放进 Row 的
                //   children 会拿到**无界宽度**约束 → debug 直接断言
                //   "BoxConstraints forces an infinite width" (test 里实测炸过),
                //   release 则静默把按钮撑成怪尺寸. 有界父 (Column / SizedBox) 才安全.
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pickProof,
                    icon: const Icon(Icons.image_outlined, size: AppSize.iconMd),
                    label: Text(
                      _proofUrl == null ? '传付款截图 (可不传)' : '已传截图 ✓',
                      style: const TextStyle(fontSize: AppTheme.fontSm),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.s16),
                SizedBox(
                  width: double.infinity,
                  height: AppTheme.buttonLgHeight,
                  child: FilledButton.icon(
                    onPressed: (_busy || products.isEmpty || (latest?.status == 'pending'))
                        ? null
                        : () {
                            final p = products.firstWhere(
                              (x) => x.planCode == selected,
                              orElse: () => products.first,
                            );
                            _submit(p);
                          },
                    icon: _busy
                        ? const SizedBox(
                            width: AppSpace.s22,
                            height: AppSpace.s22,
                            child: LoadingState(size: 24, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle_outline, size: AppSize.iconLg),
                    label: Text(
                      _busy ? '提交中...' : '我已支付',
                      style: const TextStyle(fontSize: AppTheme.fontMd),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.s8),
                const Text(
                  '说明: 内测阶段暂不支持自动续费; 需要 ¥49/月 的连续包月价, 等微信支付上线后可直接开通',
                  style: TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 大图收款码 (本站上传 / 静态兜底; 404 也不崩, 给明确提示)
class _QrImageLarge extends StatelessWidget {
  final String url;
  const _QrImageLarge({required this.url});

  @override
  Widget build(BuildContext context) {
    final abs = url.startsWith('http') ? url : '${ApiClient.baseOrigin}$url';
    return Image.network(
      abs,
      fit: BoxFit.contain,
      loadingBuilder: (c, child, progress) => progress == null
          ? child
          : const LoadingState(),
      // ⚠ 两种失败要分开说: "没配置" 由外面那段红字提示; 这里是"图片拉不到"(断网/文件被删)
      errorBuilder: (c, _, __) => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpace.s12),
          child: Text(
            '收款码加载不出来\n请检查网络, 或让管理员重新上传',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
          ),
        ),
      ),
    );
  }
}
