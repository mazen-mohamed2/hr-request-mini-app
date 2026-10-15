// Opt-in: ./tool/run_live_integration.ps1 -ValidateBackend
// Kept outside test/ so ordinary `flutter test` never needs a live server.
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_request_mobile/core/api/api_exception.dart';
import 'package:hr_request_mobile/core/auth/auth_controller.dart';
import 'package:hr_request_mobile/core/auth/auth_state.dart';
import 'package:hr_request_mobile/core/auth/token_storage.dart';
import 'package:hr_request_mobile/core/config/app_config.dart';
import 'package:hr_request_mobile/features/profile/data/profile_provider.dart';
import 'package:hr_request_mobile/features/profile/data/user_profile.dart';
import 'package:hr_request_mobile/features/requests/data/hr_request.dart';
import 'package:hr_request_mobile/features/requests/data/request_providers.dart';

// These are the existing development seed accounts, never production defaults.
const _seedPassword = 'DevPassword123!';
const _employeeEmail = 'alice@example.com';
const _otherEmployeeEmail = 'bob@example.com';
const _hrEmail = 'hr@example.com';

class _MemoryTokenStorage implements TokenStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String token) async => value = token;
  @override
  Future<void> clear() async => value = null;
}

class _Session {
  _Session() {
    const url = String.fromEnvironment('API_BASE_URL');
    if (url.isEmpty) {
      throw StateError(
        'Use tool/run_live_integration.ps1 or explicitly supply API_BASE_URL for an isolated seeded backend.',
      );
    }
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        appConfigProvider.overrideWithValue(AppConfig(apiBaseUrl: url)),
        tokenStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
  }

  final storage = _MemoryTokenStorage();
  late final ProviderContainer container;

  void keep<T>(ProviderListenable<T> provider) {
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
  }

  Future<void> signedOut() async {
    final settled = Completer<void>();
    final subscription = container.listen(authControllerProvider, (_, next) {
      if (!next.busy &&
          next.phase != AuthPhase.restoring &&
          !settled.isCompleted) {
        settled.complete();
      }
    }, fireImmediately: true);
    try {
      await settled.future.timeout(const Duration(seconds: 30));
      expect(container.read(authControllerProvider).phase, AuthPhase.signedOut);
    } finally {
      subscription.close();
    }
  }

  Future<UserProfile> login(String email) async {
    await signedOut();
    final success = await container
        .read(authControllerProvider.notifier)
        .login(email, _seedPassword);
    expect(success, isTrue, reason: 'Real seeded login must succeed.');
    final auth = container.read(authControllerProvider);
    expect(auth.phase, AuthPhase.signedIn);
    expect(auth.user?.email, email);
    // Avoid printing a real JWT even if this assertion fails.
    expect(storage.value?.isNotEmpty, isTrue);
    expect(container.read(apiClientProvider).token == storage.value, isTrue);
    return auth.user!;
  }

  Future<HrRequest> create(String subject) async {
    keep(createRequestProvider);
    final result = await container
        .read(createRequestProvider.notifier)
        .submit(
          CreateRequestInput(
            type: RequestType.employmentLetter,
            subject: subject,
            description: 'Real Flutter HTTP integration request.',
          ),
        );
    expect(result, isNotNull, reason: 'Real API creation must succeed.');
    expect(result!.status, RequestStatus.pending);
    expect(result.subject, subject);
    expect(result.description, 'Real Flutter HTTP integration request.');
    expect(result.type, RequestType.employmentLetter);
    expect(result.employeeId, container.read(authControllerProvider).user!.id);
    expect(
      result.employee?.employeeId,
      container.read(authControllerProvider).user!.employeeId,
    );
    expect(result.submittedAt, isNotNull);
    expect(result.submittedAt!.isUtc, isTrue);
    expect(result.hrComment, isNull);
    expect(result.reviewedBy, isNull);
    expect(result.reviewedAt, isNull);
    expect(result.reviewer, isNull);
    return result;
  }
}

TypeMatcher<ApiException> _apiError(int status, String code, String message) =>
    isA<ApiException>()
        .having((error) => error.statusCode, 'HTTP status', status)
        .having((error) => error.code, 'backend code', code)
        .having((error) => error.message, 'safe client message', message);

void main() {
  test(
    'real employee creation, HR approval and employee reload through Riverpod',
    () async {
      final employee = _Session();
      final alice = await employee.login(_employeeEmail);
      expect(alice.role, UserRole.employee);
      employee.keep(profileProvider);
      final profile = await employee.container.read(profileProvider.future);
      expect(profile.id, alice.id);
      expect(profile.name, 'Alice Employee');
      expect(profile.employeeId, 'EMP001');
      expect(profile.department, 'Engineering');
      expect(profile.jobTitle, 'Software Engineer');
      expect(profile.email, _employeeEmail);
      expect(profile.id, isNot(profile.employeeId));
      final listProvider = employeeRequestsProvider(1);
      employee.keep(listProvider);
      final before = await employee.container.read(listProvider.future);
      employee.container.read(employeePageProvider.notifier).goTo(2);
      final created = await employee.create('Live integration approval');
      expect(employee.container.read(employeePageProvider), 1);
      final after = await employee.container.read(listProvider.future);
      expect(after.items.map((item) => item.id), contains(created.id));
      expect(after.pagination.page, 1);
      expect(after.pagination.pageSize, 20);
      expect(after.pagination.total, before.pagination.total + 1);
      expect(after.pagination.totalPages, (after.pagination.total / 20).ceil());
      expect(
        after.items.map((item) => item.id).toSet().length,
        after.items.length,
      );
      final detailProvider = employeeDetailProvider(created.id);
      employee.keep(detailProvider);
      final pending = await employee.container.read(detailProvider.future);
      expect(pending.status, RequestStatus.pending);
      expect(pending.hrComment, isNull);
      expect(pending.reviewedBy, isNull);
      expect(pending.reviewedAt, isNull);
      expect(pending.reviewer, isNull);

      final hr = _Session();
      final reviewer = await hr.login(_hrEmail);
      expect(reviewer.role, UserRole.hr);
      final pendingProvider = pendingRequestsProvider(1);
      hr.keep(pendingProvider);
      expect(
        (await hr.container.read(
          pendingProvider.future,
        )).items.map((item) => item.id),
        contains(created.id),
      );
      final hrDetail = hrDetailProvider(created.id);
      hr.keep(hrDetail);
      expect((await hr.container.read(hrDetail.future)).employee?.id, alice.id);
      hr.keep(reviewRequestProvider(created.id));
      final approved = await hr.container
          .read(reviewRequestProvider(created.id).notifier)
          .submit(
            ReviewInput(
              status: RequestStatus.approved,
              comment: '  Employment confirmed.  ',
            ),
          );
      expect(approved?.status, RequestStatus.approved);
      expect(approved?.hrComment, 'Employment confirmed.');
      expect(approved?.reviewedBy, reviewer.id);
      expect(approved?.reviewer?.id, reviewer.id);
      expect(approved?.reviewer?.employeeId, 'HR001');
      expect(approved?.reviewedAt, isNotNull);
      expect(approved?.reviewedAt?.isUtc, isTrue);
      expect(
        (await hr.container.read(hrDetail.future)).status,
        RequestStatus.approved,
      );
      expect(
        (await hr.container.read(
          pendingProvider.future,
        )).items.map((item) => item.id),
        isNot(contains(created.id)),
      );
      final updated = await employee.container.refresh(detailProvider.future);
      expect(updated.status, RequestStatus.approved);
      expect(updated.hrComment, 'Employment confirmed.');
      expect(updated.reviewedAt, approved?.reviewedAt);
      expect(updated.reviewer?.id, reviewer.id);
      final reloadedList = await employee.container.refresh(
        listProvider.future,
      );
      expect(
        reloadedList.items.singleWhere((item) => item.id == created.id).status,
        RequestStatus.approved,
      );

      // A separate client restores the actual JWT through GET /me, over HTTP.
      final restored = _Session();
      restored.storage.value = employee.storage.value;
      final signedIn = Completer<AuthState>();
      final subscription = restored.container.listen(authControllerProvider, (
        _,
        next,
      ) {
        if (!next.busy &&
            next.phase != AuthPhase.restoring &&
            !signedIn.isCompleted) {
          signedIn.complete(next);
        }
      }, fireImmediately: true);
      addTearDown(subscription.close);
      final restoredState = await signedIn.future.timeout(
        const Duration(seconds: 30),
      );
      expect(restoredState.phase, AuthPhase.signedIn);
      expect(restoredState.user?.id, alice.id);
    },
  );

  test('real HR rejection without comment and employee reload', () async {
    final employee = _Session();
    await employee.login(_employeeEmail);
    final created = await employee.create('Live integration rejection');
    final hr = _Session();
    final reviewer = await hr.login(_hrEmail);
    final pendingProvider = pendingRequestsProvider(1);
    hr.keep(pendingProvider);
    expect(
      (await hr.container.read(
        pendingProvider.future,
      )).items.map((item) => item.id),
      contains(created.id),
    );
    expect(
      (await hr.container.read(hrDetailProvider(created.id).future)).status,
      RequestStatus.pending,
    );
    hr.keep(reviewRequestProvider(created.id));
    final rejected = await hr.container
        .read(reviewRequestProvider(created.id).notifier)
        .submit(ReviewInput(status: RequestStatus.rejected, comment: '   '));
    expect(rejected?.status, RequestStatus.rejected);
    expect(rejected?.hrComment, isNull);
    expect(rejected?.reviewedBy, reviewer.id);
    expect(rejected?.reviewedAt, isNotNull);
    expect(
      (await hr.container.read(
        pendingProvider.future,
      )).items.map((item) => item.id),
      isNot(contains(created.id)),
    );
    final detail = await employee.container.read(
      employeeDetailProvider(created.id).future,
    );
    expect(detail.status, RequestStatus.rejected);
    expect(detail.hrComment, isNull);
    expect(detail.reviewedAt?.isUtc, isTrue);
    expect(detail.reviewer?.id, reviewer.id);
  });

  test('bad real credentials map safely and leave no session', () async {
    final session = _Session();
    await session.signedOut();
    expect(
      await session.container
          .read(authControllerProvider.notifier)
          .login(_employeeEmail, 'WrongPassword123!'),
      isFalse,
    );
    final state = session.container.read(authControllerProvider);
    expect(state.phase, AuthPhase.signedOut);
    expect(
      state.error,
      _apiError(401, 'INVALID_CREDENTIALS', 'Email or password is incorrect.'),
    );
    expect(session.storage.value, isNull);
    expect(session.container.read(apiClientProvider).token, isNull);
  });

  test('missing token receives a real 401 and parses the API error', () async {
    final session = _Session();
    await session.signedOut();
    await expectLater(
      session.container.read(authRepositoryProvider).me(),
      throwsA(
        _apiError(
          401,
          'UNAUTHORIZED',
          'Your session has expired. Please sign in again.',
        ),
      ),
    );
  });

  test('employee cannot use the real HR endpoint', () async {
    final employee = _Session();
    await employee.login(_employeeEmail);
    await expectLater(
      employee.container.read(requestRepositoryProvider).pendingList(1),
      throwsA(
        _apiError(403, 'FORBIDDEN', 'You do not have permission to do this.'),
      ),
    );
    expect(
      employee.container.read(authControllerProvider).phase,
      AuthPhase.signedIn,
    );
  });

  test(
    'another employee request has the same safe 404 as a missing ID',
    () async {
      final bob = _Session();
      await bob.login(_otherEmployeeEmail);
      final created = await bob.create('Live integration ownership');
      expect(
        (await bob.container.read(
          employeeDetailProvider(created.id).future,
        )).id,
        created.id,
      );
      final alice = _Session();
      await alice.login(_employeeEmail);
      final repository = alice.container.read(requestRepositoryProvider);
      final expected = _apiError(
        404,
        'REQUEST_NOT_FOUND',
        'This request could not be found.',
      );
      await expectLater(
        repository.employeeDetail(created.id),
        throwsA(expected),
      );
      await expectLater(
        repository.employeeDetail('00000000-0000-4000-8000-000000000000'),
        throwsA(expected),
      );
      expect(
        (await repository.employeeList(1)).items.map((item) => item.id),
        isNot(contains(created.id)),
      );
    },
  );

  test('real create validation details map to safe field messages', () async {
    final employee = _Session();
    await employee.login(_employeeEmail);
    await expectLater(
      employee.container
          .read(requestRepositoryProvider)
          .create(
            const CreateRequestInput(
              type: RequestType.other,
              subject: ' ',
              description: ' ',
            ),
          ),
      throwsA(
        _apiError(
          400,
          'VALIDATION_ERROR',
          'Please check: subject, description.',
        ).having(
          (error) => error.fields,
          'validation fields',
          containsAll(['subject', 'description']),
        ),
      ),
    );
  });

  test(
    'real repeated review maps 409 and reloads the winning server state',
    () async {
      final employee = _Session();
      await employee.login(_employeeEmail);
      final created = await employee.create('Live integration conflict');
      final staleHr = _Session();
      await staleHr.login(_hrEmail);
      final detailProvider = hrDetailProvider(created.id);
      final pendingProvider = pendingRequestsProvider(1);
      staleHr.keep(detailProvider);
      staleHr.keep(pendingProvider);
      expect(
        (await staleHr.container.read(detailProvider.future)).status,
        RequestStatus.pending,
      );
      expect(
        (await staleHr.container.read(
          pendingProvider.future,
        )).items.map((item) => item.id),
        contains(created.id),
      );
      final winningHr = _Session();
      await winningHr.login(_hrEmail);
      await winningHr.container
          .read(requestRepositoryProvider)
          .review(
            created.id,
            ReviewInput(
              status: RequestStatus.approved,
              comment: 'Winning real review.',
            ),
          );
      final action = reviewRequestProvider(created.id);
      staleHr.keep(action);
      final result = await staleHr.container
          .read(action.notifier)
          .submit(ReviewInput(status: RequestStatus.rejected));
      expect(result, isNull);
      expect(
        staleHr.container.read(action).error,
        _apiError(
          409,
          'ALREADY_REVIEWED',
          'This request has already been reviewed. Its latest status will be loaded.',
        ),
      );
      final updated = await staleHr.container.read(detailProvider.future);
      expect(updated.status, RequestStatus.approved);
      expect(updated.hrComment, 'Winning real review.');
      expect(
        (await staleHr.container.read(
          pendingProvider.future,
        )).items.map((item) => item.id),
        isNot(contains(created.id)),
      );
    },
  );

  test(
    'real 401 during restoration clears the integration session boundary',
    () async {
      final session = _Session();
      session.storage.value = 'invalid-integration-session';
      await session.signedOut();
      expect(session.storage.value, isNull);
      expect(session.container.read(apiClientProvider).token, isNull);
      expect(
        session.container.read(authControllerProvider).error?.code,
        'SESSION_EXPIRED',
      );
    },
  );
}
