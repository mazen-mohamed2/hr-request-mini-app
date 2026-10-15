import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_request_mobile/core/api/api_exception.dart';
import 'package:hr_request_mobile/core/auth/auth_controller.dart';
import 'package:hr_request_mobile/core/auth/auth_state.dart';
import 'package:hr_request_mobile/features/auth/data/auth_repository.dart';
import 'support/fakes.dart';

void main() {
  test(
    'no stored token resolves to signed out without profile lookup',
    () async {
      final adapter = FakeAdapter((_) async => const Reply({}));
      final container = authContainer(adapter, MemoryTokenStorage());
      addTearDown(container.dispose);
      expect((await settleAuth(container)).phase, AuthPhase.signedOut);
      expect(adapter.requests, isEmpty);
    },
  );
  test(
    'login persists secure session and uses server user; logout clears it',
    () async {
      final storage = MemoryTokenStorage();
      final adapter = FakeAdapter(
        (_) async => Reply(body('POST /api/auth/login')),
      );
      final container = authContainer(adapter, storage);
      addTearDown(container.dispose);
      await settleAuth(container);
      expect(
        await container
            .read(authControllerProvider.notifier)
            .login('alice@example.com', 'password'),
        isTrue,
      );
      expect(container.read(authControllerProvider).user?.employeeId, 'EMP001');
      expect(storage.value, body('POST /api/auth/login')['token']);
      expect(container.read(apiClientProvider).token, storage.value);
      await container.read(authControllerProvider.notifier).logout();
      expect(storage.value, isNull);
      expect(storage.clears, 1);
      expect(container.read(apiClientProvider).token, isNull);
      expect(container.read(authControllerProvider).phase, AuthPhase.signedOut);
    },
  );
  test(
    'restoration validates saved token with /me and server-returned role',
    () async {
      final storage = MemoryTokenStorage('opaque-saved-token');
      final adapter = FakeAdapter(
        (_) async => Reply({
          'data': {
            ...body('GET /api/me')['data'] as Map<String, dynamic>,
            'role': 'HR',
          },
        }),
      );
      final container = authContainer(adapter, storage);
      addTearDown(container.dispose);
      final state = await settleAuth(container);
      expect(state.phase, AuthPhase.signedIn);
      expect(state.user?.role.apiValue, 'HR');
      expect(adapter.requests.single.uri.path, '/api/me');
      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer opaque-saved-token',
      );
    },
  );
  test(
    'invalid restored session is cleared centrally without a retry loop',
    () async {
      final storage = MemoryTokenStorage('expired-token');
      final adapter = FakeAdapter(
        (_) async => Reply(body('ERROR 401 missing token'), 401),
      );
      final container = authContainer(adapter, storage);
      addTearDown(container.dispose);
      final state = await settleAuth(container);
      expect(state.phase, AuthPhase.signedOut);
      expect(storage.value, isNull);
      expect(storage.clears, 1);
      expect(adapter.requests, hasLength(1));
      expect(state.error?.code, 'SESSION_EXPIRED');
    },
  );
  test(
    'temporary restoration failure retains token and can be retried',
    () async {
      final storage = MemoryTokenStorage('saved-token');
      final adapter = FakeAdapter(
        (_) async => const Reply({'error': <String, Object?>{}}, 503),
      );
      final container = authContainer(adapter, storage);
      addTearDown(container.dispose);
      expect((await settleAuth(container)).phase, AuthPhase.recovery);
      expect(storage.value, 'saved-token');
      expect(storage.clears, 0);
      adapter.respond = (_) async => Reply(body('GET /api/me'));
      await container.read(authControllerProvider.notifier).restore();
      expect(container.read(authControllerProvider).phase, AuthPhase.signedIn);
    },
  );
  test(
    'bad login remains signed out and does not expire another session',
    () async {
      final storage = MemoryTokenStorage();
      final adapter = FakeAdapter(
        (_) async => const Reply({
          'error': {'code': 'INVALID_CREDENTIALS'},
        }, 401),
      );
      final container = authContainer(adapter, storage);
      addTearDown(container.dispose);
      await settleAuth(container);
      expect(
        await container
            .read(authControllerProvider.notifier)
            .login('alice@example.com', 'wrong'),
        isFalse,
      );
      expect(
        container.read(authControllerProvider).error?.code,
        'INVALID_CREDENTIALS',
      );
      expect(storage.clears, 0);
      expect(storage.value, isNull);
    },
  );
  test(
    'storage write failure never exposes an authenticated session',
    () async {
      final storage = MemoryTokenStorage()..failWrite = true;
      final container = authContainer(
        FakeAdapter((_) async => Reply(body('POST /api/auth/login'))),
        storage,
      );
      addTearDown(container.dispose);
      await settleAuth(container);
      expect(
        await container
            .read(authControllerProvider.notifier)
            .login('alice@example.com', 'password'),
        isFalse,
      );
      expect(container.read(authControllerProvider).phase, AuthPhase.signedOut);
      expect(
        container.read(authControllerProvider).error?.code,
        'STORAGE_ERROR',
      );
      expect(container.read(apiClientProvider).token, isNull);
    },
  );
  test('concurrent authenticated 401s clear the session only once', () async {
    final storage = MemoryTokenStorage('saved-token');
    final adapter = FakeAdapter((_) async => Reply(body('GET /api/me')));
    final container = authContainer(adapter, storage);
    addTearDown(container.dispose);
    await settleAuth(container);
    adapter.respond = (_) async => Reply(body('ERROR 401 missing token'), 401);
    final repository = container.read(authRepositoryProvider);
    final failures = await Future.wait([
      repository.me().then<Object>((value) => value, onError: (Object e) => e),
      repository.me().then<Object>((value) => value, onError: (Object e) => e),
    ]);
    expect(failures, everyElement(isA<ApiException>()));
    expect(storage.clears, 1);
    expect((await settleAuth(container)).phase, AuthPhase.signedOut);
  });
  test('late old-session 401 cannot sign out a new login', () async {
    final storage = MemoryTokenStorage('old-token');
    final delayed = Completer<Reply>();
    final started = Completer<void>();
    final adapter = FakeAdapter((_) async => Reply(body('GET /api/me')));
    final container = authContainer(adapter, storage);
    addTearDown(container.dispose);
    await settleAuth(container);
    adapter.respond = (_) {
      started.complete();
      return delayed.future;
    };
    final old = AuthRepository(
      container.read(apiClientProvider),
    ).me().then<Object>((value) => value, onError: (Object e) => e);
    await started.future;
    await container.read(authControllerProvider.notifier).logout();
    adapter.respond = (_) async =>
        Reply({...body('POST /api/auth/login'), 'token': 'new-token'});
    await container
        .read(authControllerProvider.notifier)
        .login('alice@example.com', 'password');
    delayed.complete(Reply(body('ERROR 401 missing token'), 401));
    await old;
    expect(container.read(authControllerProvider).phase, AuthPhase.signedIn);
    expect(storage.value, 'new-token');
    expect(storage.clears, 1);
  });
  test(
    'logout while login is in flight cannot restore the old login',
    () async {
      final delayed = Completer<Reply>();
      final storage = MemoryTokenStorage();
      final container = authContainer(
        FakeAdapter((_) => delayed.future),
        storage,
      );
      addTearDown(container.dispose);
      await settleAuth(container);
      final login = container
          .read(authControllerProvider.notifier)
          .login('alice@example.com', 'password');
      await container.read(authControllerProvider.notifier).logout();
      delayed.complete(Reply(body('POST /api/auth/login')));
      expect(await login, isFalse);
      expect(storage.value, isNull);
      expect(container.read(authControllerProvider).phase, AuthPhase.signedOut);
    },
  );
}
