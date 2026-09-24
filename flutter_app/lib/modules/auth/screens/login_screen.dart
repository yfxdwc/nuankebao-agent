// ============================================
// 登录页 (B2 换装, 2026-09-25)
//   主人原话: 「这是门面」 —— 暖客宝 / 大健康气质 (温暖, 不冷峻)
//   B2 收口: 黑色 / 灰色硬编码 → AppColors.* / context.tokens.* 令牌
//   主按钮 → FilledButton (B 档) + minimumSize(buttonLgHeight)
// 行为完全保留 (邀请制, 账号/手机号 + 密码, 错误显示, 推荐码注册入口)
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/http/api_client.dart';
import '../../../core/telemetry/usage_providers.dart';
import '../../../core/theme/theme_ext.dart';

import '../../../core/theme/tokens.g.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;
    if (identifier.isEmpty) {
      _showError('请输入账号或手机号');
      ref.read(usageServiceProvider).track('login_fail',
          errorCode: 'missing_identifier',
          props: {'reason': 'missing_identifier'});
      return;
    }
    if (password.isEmpty) {
      _showError('请输入密码');
      ref.read(usageServiceProvider).track('login_fail',
          errorCode: 'missing_password',
          props: {'reason': 'missing_password'});
      return;
    }

    setState(() => loading = true);
    try {
      await ref.read(authProvider.notifier).login(
            identifier: identifier,
            password: password,
          );
      final state = ref.read(authProvider);
      if (state.error != null) {
        ref.read(usageServiceProvider).track('login_fail',
            errorCode: 'auth_error', props: {'reason': 'auth_error'});
        if (mounted) _showError(state.error!);
      } else if (state.isLoggedIn) {
        ref.read(usageServiceProvider).track('login_success');
        if (mounted) context.go('/customers');
      }
    } catch (e) {
      ref.read(usageServiceProvider).track('login_fail',
          errorCode: 'network_error', props: {'reason': 'network_error'});
      if (mounted) _showError('登录异常: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.s24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Image.asset(
                    'assets/icons/nuankebao-logo.png',
                    width: AppSpace.s96,
                    height: AppSpace.s96,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: AppSpace.s16),
                  Text(
                    '暖客宝',
                    style: TextStyle(
                      fontSize: AppType.xxl,
                      fontWeight: AppWeight.bold,
                      color: tokens.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpace.s8),
                  const Text(
                    '大健康客户管理 · AI 助手',
                    style: TextStyle(
                      fontSize: AppType.sm,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpace.s48),
                  _buildForm(authState),
                  const SizedBox(height: AppSpace.s24),
                  // 诊断信息: 当前连的后端地址 (登录不上时对照确认装对 APK)
                  Text(
                    ApiClient.baseUrl,
                    style: const TextStyle(
                      fontSize: AppType.micro,
                      color: AppColors.textTertiary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(AuthState authState) {
    final tokens = context.tokens;
    return Column(
      children: <Widget>[
        // 输入框高度统一 AppSize.fieldLg (52), token 化的热区
        TextField(
          controller: _identifierController,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.next,
          style: const TextStyle(
            fontSize: AppType.md,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            labelText: '账号 / 手机号',
            hintText: 'admin 或 13800138000',
            prefixIcon: const Icon(Icons.person_outline,
                size: AppSize.iconLg, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: AppSpace.s16),
        TextField(
          controller: _passwordController,
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => loading ? null : _login(),
          style: const TextStyle(
            fontSize: AppType.md,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            labelText: '密码',
            prefixIcon: const Icon(Icons.lock_outline,
                size: AppSize.iconLg, color: AppColors.textSecondary),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.textSecondary),
              tooltip: _obscure ? '显示密码' : '隐藏密码',
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        if (authState.error != null) ...<Widget>[
          const SizedBox(height: AppSpace.s12),
          Text(
            authState.error!,
            style: TextStyle(
              color: tokens.danger,
              fontSize: AppType.xs,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: AppSpace.s20),
        // 主按钮 → FilledButton (B 档), 高度 buttonLgHeight (48)
        FilledButton(
          onPressed: loading ? null : _login,
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, AppSize.buttonLgHeight),
          ),
          child: loading
              ? const SizedBox(
                  width: AppSize.iconLg,
                  height: AppSize.iconLg,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Text('登录'),
        ),
        const SizedBox(height: AppSpace.s12),
        // 新用户入口 (推荐码注册) —— 仍按主人 2026-09-20 的要求放这里
        OutlinedButton.icon(
          onPressed: loading ? null : () => context.push('/register'),
          icon: const Icon(Icons.person_add_alt_1, size: AppSize.iconLg),
          label: const Text('有新推荐码? 去注册'),
          style: OutlinedButton.styleFrom(
            minimumSize:
                const Size(double.infinity, AppSize.buttonMinHeight),
            foregroundColor: tokens.primaryDark,
            side: BorderSide(color: tokens.primaryLight),
          ),
        ),
        const SizedBox(height: AppSpace.s12),
        const Text(
          '老账号忘记密码请联系管理员重置; 新用户需要朋友的推荐码才能注册',
          style: TextStyle(
            fontSize: AppType.micro,
            color: AppColors.textTertiary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
