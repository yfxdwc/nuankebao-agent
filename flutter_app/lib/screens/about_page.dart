// ============================================
// 关于与帮助 (「我的」→ 关于与帮助)
// ============================================
// 目标用户是中年女性销售 + 客服, 遇到问题不会看文档, 所以这里放的是:
//   1. 她们最常问的「怎么用」(折叠式, 一条一句大白话)
//   2. 数据去哪了 / 安不安全 (客户会问她们, 她们得答得上来)
//   3. 出问题了怎么找管理员 (复制诊断信息, 不用教怎么描述故障)
//
// 不写"隐私政策"字样: 那是法务文本, 现在没有正式版本 (docs/security-compliance.md
// 是内部方案). 这里只讲**事实**: 数据存在哪、怎么加密、谁能看。
//
// 数据源: 全部静态文案 (不联网) + package_info 版本号

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/http/session_token.dart';
import '../core/providers/service_providers.dart';
import '../core/theme/app_theme.dart';
import 'profile_sheets.dart';
import 'profile_widgets.dart';

import '../core/theme/tokens.g.dart';
final _packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoAsync = ref.watch(_packageInfoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('关于与帮助'), toolbarHeight: AppSize.appBarHeight),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.s16, 16, 16, 32),
        children: [
          // 顶部: 品牌 + 版本
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.s20),
              child: Column(
                children: [
                  Container(
                    width: AppSpace.s72,
                    height: AppSpace.s72,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(AppRadius.r20),
                    ),
                    child: const Icon(Icons.spa,
                        size: AppSize.avatarMd, color: AppTheme.primaryDark),
                  ),
                  const SizedBox(height: AppSpace.s12),
                  const Text(
                    '暖客宝',
                    style: TextStyle(
                      fontSize: AppTheme.fontXl,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpace.s4),
                  const Text(
                    '大健康销售 · 客户维护 · 养生记录',
                    style: TextStyle(
                      fontSize: AppTheme.fontSm,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpace.s12),
                  infoAsync.when(
                    loading: () => const Text(
                      '版本读取中...',
                      style: TextStyle(fontSize: AppTheme.fontSm),
                    ),
                    error: (_, __) => const Text(
                      '版本读取失败',
                      style: TextStyle(fontSize: AppTheme.fontSm),
                    ),
                    data: (info) => Column(
                      children: [
                        Text(
                          '版本 v${info.version} (${info.buildNumber})',
                          style: const TextStyle(
                            fontSize: AppTheme.fontMd,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryDark,
                          ),
                        ),
                        const SizedBox(height: AppSpace.s4),
                        Text(
                          installInfoLine(
                            packageName: info.packageName,
                            version: info.version,
                            buildNumber: info.buildNumber,
                            buildSignature: info.buildSignature,
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: AppTheme.fontXs,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpace.s4),
                  Text(
                    kIsWeb
                        ? '运行环境: Web 预览'
                        : '运行环境: ${defaultTargetPlatform.name}',
                    style: const TextStyle(
                      fontSize: AppTheme.fontXs,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          profileSectionGap,

          // 使用帮助
          ProfileSection(
            title: '使用帮助',
            icon: Icons.help_outline,
            hint: '点开看',
            children: const [
              _HelpItem(
                question: '怎么给客户记一次养生/服务?',
                answer: '客户页找到这位客户 → 点客户卡片进详情 → 点右下角「+ 添加记录」→ '
                    '选部位/状态/用料, 保存。记完会自动进客户的历史, 下次谈单直接翻。',
              ),
              _HelpItem(
                question: '客户太多找不到人怎么办?',
                answer: '客户页最上面的搜索框, 输入姓名或手机号任意一段就行。'
                    '上面的胶囊按键可以只看「加盟」「种子」「普通」。',
              ),
              _HelpItem(
                question: '「加盟 / 种子 / 普通」是什么意思?',
                answer: '加盟 = 您下面的加盟商 (也当客户维护着); 种子 = 还没成交的潜在客户; '
                    '普通 = 已经在维护的客户。客户表单里可以勾「种子客户」。',
              ),
              _HelpItem(
                question: '怎么看我的上下级关系?',
                answer: '「我的」页 → 我的加盟网络; 或在客户页切到「图谱」视图, '
                    '能一眼看到谁在您的 A 线、谁在 B 线, 点节点可以看详情。',
              ),
              _HelpItem(
                question: '怎么提醒我该跟进谁?',
                answer: '客户详情页 → 「AI 跟进建议」会给话术, 生成后可以直接「建跟进任务」, '
                    '选好几天后提醒。客户资料里填了生日的, 生日前也会在客户页提醒。',
              ),
              _HelpItem(
                question: '手机换了/重装了, 数据还在吗?',
                answer: '在。数据都存在公司自己的服务器上, 换手机用同一个手机号登录就都在, '
                    '不用备份, 也不用导出。',
              ),
            ],
          ),
          profileSectionGap,

          // 数据安全说明 (客户问起来, 销售要答得上来)
          ProfileSection(
            title: '数据安全说明',
            icon: Icons.shield_outlined,
            children: const [
              _FactItem(
                icon: Icons.dns_outlined,
                title: '存在公司自己的服务器',
                detail: '客户资料不上传到任何第三方云盘或平台, 不卖给外部。',
              ),
              _FactItem(
                icon: Icons.lock_outline,
                title: '手机号和健康信息加密保存',
                detail: '手机号、既往病史、养生记录内容在数据库里是加密存的, '
                    '直接看数据库文件也读不出明文。',
              ),
              _FactItem(
                icon: Icons.visibility_outlined,
                title: '谁能看到客户',
                detail: '只有同一门店/自己名下的客户能看到 (按账号权限控制), '
                    '管理员有查看权限但每次查看都会留痕。',
              ),
              _FactItem(
                icon: Icons.history,
                title: '改动都有记录',
                detail: '新增/修改/删除客户和记录都会写审计日志 (谁、什么时候、改了什么), '
                    '方便追溯。',
              ),
              _FactItem(
                icon: Icons.backup_outlined,
                title: '每天自动备份',
                detail: '数据库每天凌晨自动备份, 并异地留存, 误删也能找回来。',
              ),
            ],
          ),
          profileSectionGap,

          // 遇到问题
          ProfileSection(
            title: '遇到问题',
            icon: Icons.support_agent,
            children: [
              ProfileTile(
                icon: Icons.wifi_find,
                title: '做一次网络自检',
                subtitle: '当场测服务器通不通、快不快',
                onTap: () => showDiagnosticsSheet(context, ref),
              ),
              ProfileTile(
                icon: Icons.content_copy,
                title: '复制诊断信息发给管理员',
                subtitle: '版本 / 账号 / 服务地址 / 连接状态',
                color: AppTheme.accent,
                onTap: () async {
                  final text = await buildDiagnosticText(
                    ref,
                    ref.read(meProfileProvider),
                  );
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('诊断信息已复制, 可发给管理员',
                            style: TextStyle(fontSize: AppTheme.fontMd)),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpace.s24),
          const Center(
            child: Text(
              '暖客宝 · 数据自托管',
              style: TextStyle(
                fontSize: AppTheme.fontXs,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 使用帮助的一条 (折叠)
class _HelpItem extends StatelessWidget {
  final String question;
  final String answer;

  const _HelpItem({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return Theme(
      // 展开箭头默认在右边, 中老年用户习惯点整行 → 去掉 ExpansionTile 的分割线
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: AppSpace.s12),
        iconColor: AppTheme.primary,
        collapsedIconColor: AppTheme.textSecondary,
        title: Text(
          question,
          style: const TextStyle(
            fontSize: AppTheme.fontMd,
            fontWeight: FontWeight.w500,
            color: AppTheme.textPrimary,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              answer,
              style: const TextStyle(
                fontSize: AppTheme.fontSm,
                height: 1.6,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 数据安全说明的一条 (不折叠, 直接看得见)
class _FactItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _FactItem({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppSize.iconLg, color: AppTheme.primary),
          const SizedBox(width: AppSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: AppTheme.fontMd,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpace.s2),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: AppTheme.fontXs,
                    height: 1.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
