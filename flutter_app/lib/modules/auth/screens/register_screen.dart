// ============================================
// 注册页 (B1: 凭推荐码自助注册, 主人 2026-09-20 拍)
// ============================================
// 为什么有注册页 (原来是纯邀请制, 账号只能管理员建):
//   主人问「登录界面里没有注册账户的入口，新用户怎么注册？」→ 选 B1:
//   新人**填朋友的推荐码**自助注册, 但**推荐人点"这是我朋友"确认后**才发 15 天会员。
//   → 没推荐码注册不了 (等于每个新人都有人背书), 也不再把建号卡在管理员身上。
//
// 主人 2026-09-20 补充要求: 「账号/用户名提醒用户填真实姓名，真实手机号」
//   → 姓名/手机号字段都带明确提示 (管理员要靠它核对身份; 手机号就是登录账号)
//   → 服务端也会强校验 (纯数字名 / 假号 都会被拒), 前端提示只是提前让人别填错
//
// 边界: 注册成功**不代表立刻有会员** —— 页面明确写"等推荐人确认"。
//      注册成功后自动用 手机号+密码 登录 (走正常登录链路, 不新造 token 通道)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/app_theme.dart';

import '../../../core/theme/tokens.g.dart';
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.initialCode});

  /// 从登录页带过来的推荐码 (可选, 预填)
  final String? initialCode;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  late final TextEditingController _codeCtrl =
      TextEditingController(text: widget.initialCode ?? '');
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _pwd2Ctrl = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _pwdCtrl.dispose();
    _pwd2Ctrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: const TextStyle(fontSize: AppTheme.fontMd))),
    );
  }

  Future<void> _submit() async {
    final code = _codeCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final pwd = _pwdCtrl.text;
    final pwd2 = _pwd2Ctrl.text;

    if (code.isEmpty) return _toast('请填推荐码 (找推荐人拿 6 位码)');
    if (name.isEmpty) return _toast('请填真实姓名');
    if (phone.isEmpty) return _toast('请填真实手机号');
    if (pwd.isEmpty) return _toast('请设置密码');
    if (pwd != pwd2) return _toast('两次填的密码不一样');

    setState(() => _busy = true);
    final r = await ref.read(billingServiceProvider).registerWithCode(
          code: code,
          name: name,
          phone: phone,
          password: pwd,
        );
    if (!mounted) return;

    if (!r.ok) {
      setState(() => _busy = false);
      return _toast(r.message);
    }

    // 注册成功 → 用手机号+密码走正常登录 (不新造 token 通道)
    await ref.read(authProvider.notifier).login(
          identifier: r.username ?? phone,
          password: pwd,
        );
    if (!mounted) return;
    setState(() => _busy = false);

    final state = ref.read(authProvider);
    if (state.isLoggedIn) {
      _toast(r.message); // "等推荐人确认" 这句要让用户看到
      context.go('/customers');
    } else {
      _toast('注册成功, 请用手机号和密码登录');
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgWarm,
      appBar: AppBar(title: const Text('注册账号'), toolbarHeight: 64),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.s20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpace.s12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(AppRadius.r12),
                ),
                child: const Text(
                  '暖客宝是邀请制: 填朋友的 6 位推荐码就能注册。\n'
                  '推荐人点「这是我朋友」确认后, 你会得到 15 天会员体验。',
                  style: TextStyle(fontSize: AppTheme.fontSm, height: 1.6),
                ),
              ),
              const SizedBox(height: AppSpace.s20),

              TextField(
                controller: _codeCtrl,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                style: const TextStyle(
                  fontSize: AppTheme.fontXl,
                  letterSpacing: 4,
                  fontWeight: FontWeight.w600,
                ),
                decoration: const InputDecoration(
                  labelText: '推荐码 *',
                  hintText: '6 位字母数字',
                  helperText: '找推荐人拿; 没有码不能注册',
                  counterText: '',
                  prefixIcon: Icon(Icons.card_giftcard),
                ),
              ),
              const SizedBox(height: AppSpace.s16),

              TextField(
                controller: _nameCtrl,
                textInputAction: TextInputAction.next,
                style: const TextStyle(fontSize: AppTheme.fontMd),
                decoration: const InputDecoration(
                  labelText: '真实姓名 *',
                  hintText: '例: 王秀英',
                  // 主人要求: 提醒填真实姓名 (管理员要靠它核对)
                  helperText: '请填真实姓名 — 管理员要用它核对身份, 别填昵称/网名',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: AppSpace.s16),

              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                style: const TextStyle(fontSize: AppTheme.fontMd),
                decoration: const InputDecoration(
                  labelText: '真实手机号 *',
                  hintText: '11 位手机号',
                  // 主人要求: 提醒填真实手机号 (就是登录账号)
                  helperText: '请填真实手机号 — 它就是你的登录账号, 也是找回账号的凭据',
                  prefixIcon: Icon(Icons.phone_iphone),
                ),
              ),
              const SizedBox(height: AppSpace.s16),

              TextField(
                controller: _pwdCtrl,
                obscureText: _obscure,
                style: const TextStyle(fontSize: AppTheme.fontMd),
                decoration: InputDecoration(
                  labelText: '设置密码 *',
                  helperText: '至少 8 位, 含字母和数字',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.s16),

              TextField(
                controller: _pwd2Ctrl,
                obscureText: _obscure,
                style: const TextStyle(fontSize: AppTheme.fontMd),
                decoration: const InputDecoration(
                  labelText: '再填一次密码 *',
                  prefixIcon: Icon(Icons.lock_reset),
                ),
              ),
              const SizedBox(height: AppSpace.s24),

              SizedBox(
                width: double.infinity,
                height: AppTheme.buttonLgHeight,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: _busy
                      ? const SizedBox(
                          width: AppSpace.s22,
                          height: AppSpace.s22,
                          child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                        )
                      : const Icon(Icons.person_add_alt_1, size: 26),
                  label: Text(_busy ? '注册中...' : '注册',
                      style: const TextStyle(fontSize: AppTheme.fontMd)),
                ),
              ),
              const SizedBox(height: AppSpace.s12),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : () => context.go('/login'),
                  child: const Text('已有账号? 去登录',
                      style: TextStyle(fontSize: AppTheme.fontSm)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
