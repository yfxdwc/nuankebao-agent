import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  String _step = 'phone'; // 'phone' | 'code'
  bool loading = false; // W12: 修 _login 错误显示

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (phone.length != 11) {
      _showError('请输入 11 位手机号');
      return;
    }
    // W1: mock 验证码 (W2 替换为真实 SMS)
    setState(() => _step = 'code');
    _showSnack('验证码已发送 (开发期: 123456)');
  }

  Future<void> _login() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      _showError('请输入 6 位验证码');
      return;
    }
    setState(() => loading = true);
    try {
      await ref.read(authProvider.notifier).login(
        phone: _phoneController.text.trim(),
        code: code,
      );
      final state = ref.read(authProvider);
      if (state.error != null) {
        if (mounted) _showError(state.error!);
      } else if (state.isLoggedIn) {
        if (mounted) context.go('/dashboard');
      }
    } catch (e) {
      if (mounted) _showError('登录异常: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showSnack(String msg) {
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
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/icons/nuankebao-logo.png',
                    width: 96,
                    height: 96,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 16),
                  const Text('暖客宝', style: TextStyle(
                    fontSize: 32, fontWeight: FontWeight.bold, color: AppTheme.primary,
                  )),
                  const SizedBox(height: 8),
                  const Text('大健康行业销售 CRM', style: TextStyle(color: Colors.black54)),
                  const SizedBox(height: 48),
                  if (_step == 'phone') _buildPhoneStep(),
                  if (_step == 'code') _buildCodeStep(authState.loading, error: authState.error),
                  const SizedBox(height: 24),
                  // 诊断信息: 当前连的后端地址 (登录不上时对照确认装对 APK)
                  Text(
                    ApiClient.baseUrl,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
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

  Widget _buildPhoneStep() {
    return Column(
      children: [
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          maxLength: 11,
          decoration: const InputDecoration(
            labelText: '手机号',
            hintText: '13800138000',
            prefixIcon: Icon(Icons.phone),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _phoneController.text.length == 11 ? _sendCode : null,
          child: const Text('发送验证码'),
        ),
      ],
    );
  }

  Widget _buildCodeStep(bool loading, {String? error}) {
    return Column(
      children: [
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(
            labelText: '验证码',
            hintText: '6 位',
            prefixIcon: const Icon(Icons.sms),
            helperText: '已发送至 +86 ${_phoneController.text}',
          ),
          autofocus: true,
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error,
            style: const TextStyle(color: Colors.red, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: loading ? null : _login,
          child: loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('登录'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _step = 'phone'),
          child: const Text('返回上一步'),
        ),
      ],
    );
  }
}
