import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/http/api_client.dart';
import '../../../core/telemetry/usage_providers.dart';
import '../../../core/theme/app_theme.dart';

import '../../../core/theme/tokens.g.dart';
/// 登录页 (2026-09-19 P2: 手机号+验证码 → 账号/手机号 + 密码)
///
/// 设计来源: docs/deploy/production-plan.md §1.1
///   - 邀请制: 账号由管理员创建, 不开放自助注册
///   - identifier = 登录名 (如 admin) 或 手机号
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
        // fix-route: /dashboard 已删 (router 只留 客户/我的 两 tab) → 登录后回客户页
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

    return Scaffold(
      backgroundColor: AppTheme.bgWarm,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.s24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/icons/nuankebao-logo.png',
                    width: AppSpace.s96,
                    height: AppSpace.s96,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: AppSpace.s16),
                  const Text('暖客宝', style: TextStyle(
                    fontSize: AppType.xxl, fontWeight: FontWeight.bold, color: AppTheme.primary,
                  )),
                  const SizedBox(height: AppSpace.s8),
                  const Text('大健康客户管理・AI助手', style: TextStyle(color: Colors.black54)),
                  const SizedBox(height: AppSpace.s48),
                  _buildForm(authState),
                  const SizedBox(height: AppSpace.s24),
                  // 诊断信息: 当前连的后端地址 (登录不上时对照确认装对 APK)
                  Text(
                    ApiClient.baseUrl,
                    style: TextStyle(fontSize: AppType.micro, color: Colors.grey.shade500),
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
    return Column(
      children: [
        TextField(
          controller: _identifierController,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: '账号 / 手机号',
            hintText: 'admin 或 13800138000',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: AppSpace.s16),
        TextField(
          controller: _passwordController,
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => loading ? null : _login(),
          decoration: InputDecoration(
            labelText: '密码',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
              tooltip: _obscure ? '显示密码' : '隐藏密码',
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        if (authState.error != null) ...[
          const SizedBox(height: AppSpace.s12),
          Text(
            authState.error!,
            style: const TextStyle(color: Colors.red, fontSize: AppType.xs),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: AppSpace.s20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: loading ? null : _login,
            child: loading
                ? const SizedBox(
                    width: AppSpace.s20,
                    height: AppSpace.s20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('登录'),
          ),
        ),
        const SizedBox(height: AppSpace.s12),

        // ★ 新用户入口 (B1, 主人 2026-09-20): 填朋友的推荐码自助注册
        //   为什么放在登录页而不是单独藏起来: 新用户第一次打开 App 就落在这里,
        //   找不到入口 = 以为要托人代建。注册完由推荐人确认 (页面上有说明)。
        OutlinedButton.icon(
          onPressed: loading ? null : () => context.push('/register'),
          icon: const Icon(Icons.person_add_alt_1, size: 22),
          label: const Text('有新推荐码? 去注册',
              style: TextStyle(fontSize: AppTheme.fontMd)),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, AppTheme.buttonMinHeight),
            foregroundColor: AppTheme.primaryDark,
            side: const BorderSide(color: AppTheme.primaryLight, width: AppSpace.s2),
          ),
        ),
        const SizedBox(height: AppSpace.s12),
        const Text(
          '老账号忘记密码请联系管理员重置; 新用户需要朋友的推荐码才能注册',
          style: TextStyle(fontSize: AppType.micro, color: Colors.black45),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
