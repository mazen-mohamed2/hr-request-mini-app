import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_request_mobile/core/api/api_client.dart';
import 'package:hr_request_mobile/core/api/json.dart';
import 'package:hr_request_mobile/core/auth/auth_controller.dart';
import 'package:hr_request_mobile/core/auth/auth_state.dart';
import 'package:hr_request_mobile/core/auth/token_storage.dart';
import 'package:hr_request_mobile/core/config/app_config.dart';
import 'package:hr_request_mobile/features/profile/data/user_profile.dart';

final Json captured = jsonObject(
  jsonDecode(
    File('test/fixtures/api-contract.examples.json').readAsStringSync(),
  ),
);
Json body(String route) =>
    jsonObject(jsonObject(jsonObject(captured['responses'])[route])['body']);
UserProfile employee() =>
    UserProfile.fromJson(jsonObject(body('GET /api/me')['data']));
UserProfile hrUser() => UserProfile.fromJson(
  jsonObject(
    jsonObject(body('PATCH /api/hr/requests/:id/review')['data'])['reviewer'],
  ),
);

class Reply {
  const Reply(this.body, [this.status = 200]);
  final Object body;
  final int status;
}

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.respond);
  Future<Reply> Function(RequestOptions) respond;
  final List<RequestOptions> requests = [];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final reply = await respond(options);
    return ResponseBody.fromString(
      jsonEncode(reply.body),
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class MemoryTokenStorage implements TokenStorage {
  MemoryTokenStorage([this.value]);
  String? value;
  int clears = 0, writes = 0;
  bool failWrite = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String token) async {
    writes++;
    if (failWrite) throw StateError('Storage unavailable');
    value = token;
  }

  @override
  Future<void> clear() async {
    clears++;
    value = null;
  }
}

ApiClient fakeApi(FakeAdapter adapter) => ApiClient(
  AppConfig(apiBaseUrl: 'https://example.test/api'),
  dio: Dio()..httpClientAdapter = adapter,
);

ProviderContainer authContainer(
  FakeAdapter adapter,
  MemoryTokenStorage storage,
) => ProviderContainer(
  retry: (_, _) => null,
  overrides: [
    tokenStorageProvider.overrideWithValue(storage),
    apiClientProvider.overrideWith((ref) {
      final api = fakeApi(adapter);
      api.onUnauthorized = (token) =>
          ref.read(authControllerProvider.notifier).expire(token);
      ref.onDispose(api.close);
      return api;
    }),
  ],
);

Future<AuthState> settleAuth(ProviderContainer container) async {
  for (var i = 0; i < 100; i++) {
    final state = container.read(authControllerProvider);
    if (state.phase != AuthPhase.restoring && !state.busy) return state;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  throw TestFailure('Authentication did not settle.');
}

class FixedAuth extends AuthController {
  FixedAuth(this.initial);
  final UserProfile initial;
  @override
  AuthState build() => AuthState(AuthPhase.signedIn, user: initial);
}

class SignedOutAuth extends AuthController {
  @override
  AuthState build() => const AuthState(AuthPhase.signedOut);
}

class SwitchingAuth extends AuthController {
  @override
  AuthState build() => AuthState(AuthPhase.signedIn, user: employee());
  void signOut() => state = const AuthState(AuthPhase.signedOut);
}
