import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api.dart';
import 'service_providers.dart';

class AuthState {
  final bool isLoggedIn;
  final bool loading;
  final String? error;

  const AuthState({
    this.isLoggedIn = false,
    this.loading = false,
    this.error,
  });

  AuthState copyWith({bool? isLoggedIn, bool? loading, String? error, bool clearError = false}) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _auth;
  AuthNotifier(this._auth) : super(const AuthState()) {
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    final logged = await _auth.isLoggedIn();
    state = state.copyWith(isLoggedIn: logged);
  }

  Future<void> login({required String phone, required String code}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      await _auth.login(phone: phone, code: code);
      state = state.copyWith(isLoggedIn: true, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> logout() async {
    await _auth.logout();
    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authServiceProvider));
});
