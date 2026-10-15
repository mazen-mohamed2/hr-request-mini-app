import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/data/auth_repository.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../config/app_config.dart';
import 'auth_state.dart';
import 'token_storage.dart';

final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);
final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => SecureTokenStorage(),
);
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(ref.watch(appConfigProvider));
  client.onUnauthorized = (token) =>
      ref.read(authControllerProvider.notifier).expire(token);
  ref.onDispose(client.close);
  return client;
});
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);
final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  int _generation = 0;
  bool _disposed = false;
  Future<void> _storageTail = Future.value();

  @override
  AuthState build() {
    ref.onDispose(() {
      _disposed = true;
      _generation++;
    });
    unawaited(Future.microtask(restore));
    return const AuthState(AuthPhase.restoring);
  }

  bool _current(int generation) => !_disposed && generation == _generation;
  Future<void> _store(Future<void> Function() action) {
    final operation = _storageTail.then((_) => action());
    _storageTail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> restore() async {
    if (_disposed || state.busy) return;
    final generation = ++_generation;
    state = const AuthState(AuthPhase.restoring, busy: true);
    final api = ref.read(apiClientProvider);
    try {
      final token = await ref.read(tokenStorageProvider).read();
      if (!_current(generation)) return;
      if (token == null || token.isEmpty) {
        api.token = null;
        state = const AuthState(AuthPhase.signedOut);
        return;
      }
      api.token = token;
      final user = await ref.read(authRepositoryProvider).me();
      if (_current(generation)) {
        state = AuthState(AuthPhase.signedIn, user: user);
      }
    } catch (error) {
      if (!_current(generation)) return;
      if (error is ApiException && error.statusCode == 401) {
        await logout();
      } else {
        // Keep a saved session on temporary network failure; offer retry/logout.
        state = AuthState(
          AuthPhase.recovery,
          error: error is ApiException ? error : ApiException.storage,
        );
      }
    }
  }

  Future<bool> login(String email, String password) async {
    if (_disposed || state.busy) return false;
    final generation = ++_generation;
    state = const AuthState(AuthPhase.signedOut, busy: true);
    try {
      final result = await ref
          .read(authRepositoryProvider)
          .login(email, password);
      if (!_current(generation)) return false;
      final storage = ref.read(tokenStorageProvider);
      try {
        await _store(() async {
          if (_current(generation)) await storage.write(result.token);
        });
      } catch (_) {
        throw ApiException.storage;
      }
      if (!_current(generation)) return false;
      ref.read(apiClientProvider).token = result.token;
      state = AuthState(AuthPhase.signedIn, user: result.user);
      return true;
    } catch (error) {
      if (_current(generation)) {
        state = AuthState(AuthPhase.signedOut, error: ApiException.from(error));
      }
      return false;
    }
  }

  Future<void> expire(String rejectedToken) async {
    if (_disposed || ref.read(apiClientProvider).token != rejectedToken) return;
    await _clear(
      const ApiException(
        'SESSION_EXPIRED',
        'Your session has expired. Please sign in again.',
      ),
    );
  }

  Future<void> logout() => _clear(null);

  Future<void> _clear(ApiException? message) async {
    if (_disposed) return;
    final generation = ++_generation;
    final storage = ref.read(tokenStorageProvider);
    ref.read(apiClientProvider).token = null;
    state = AuthState(AuthPhase.signedOut, busy: true, error: message);
    ApiException? failure;
    try {
      await _store(storage.clear);
    } catch (_) {
      failure = ApiException.storage;
    }
    if (_current(generation)) {
      state = AuthState(AuthPhase.signedOut, error: failure ?? message);
    }
  }
}
