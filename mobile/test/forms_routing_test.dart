import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_request_mobile/app.dart';
import 'package:hr_request_mobile/core/auth/auth_controller.dart';
import 'package:hr_request_mobile/core/auth/auth_state.dart';
import 'package:hr_request_mobile/core/router/app_router.dart';
import 'package:hr_request_mobile/core/theme/app_theme.dart';
import 'package:hr_request_mobile/core/widgets/form_validation.dart';
import 'package:hr_request_mobile/features/auth/presentation/login_screen.dart';
import 'package:hr_request_mobile/features/requests/presentation/create_request_screen.dart';
import 'support/fakes.dart';

void main() {
  testWidgets(
    'employee creates a request, opens detail and returns to the refreshed list',
    (tester) async {
      var created = false;
      final adapter = FakeAdapter((options) async {
        if (options.method == 'POST') {
          created = true;
          return Reply(body('POST /api/requests'), 201);
        }
        if (options.path == 'requests') {
          return Reply(
            created
                ? body('GET /api/requests')
                : {
                    'data': <Object?>[],
                    'pagination': {
                      'page': 1,
                      'pageSize': 20,
                      'total': 0,
                      'totalPages': 0,
                    },
                  },
          );
        }
        return Reply(body('GET /api/requests/:id'));
      });
      final api = fakeApi(adapter);
      addTearDown(api.close);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            authControllerProvider.overrideWith(() => FixedAuth(employee())),
            apiClientProvider.overrideWithValue(api),
          ],
          child: const HrRequestApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('New request'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('request-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Employment Letter').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('request-subject')),
        'Employment confirmation',
      );
      await tester.enterText(
        find.byKey(const Key('request-description')),
        'Please issue my employment letter.',
      );
      await tester.ensureVisible(find.byKey(const Key('request-submit')));
      await tester.tap(find.byKey(const Key('request-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Request details'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(
        adapter.requests.where((item) => item.method == 'POST'),
        hasLength(1),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Employment confirmation'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'HR confirms review, sees updated detail and returns to refreshed pending list',
    (tester) async {
      var reviewed = false;
      final adapter = FakeAdapter((options) async {
        if (options.method == 'PATCH') {
          reviewed = true;
          return Reply(body('PATCH /api/hr/requests/:id/review'));
        }
        if (options.path == 'hr/requests') {
          return Reply(
            reviewed
                ? {
                    'data': <Object?>[],
                    'pagination': {
                      'page': 1,
                      'pageSize': 20,
                      'total': 0,
                      'totalPages': 0,
                    },
                  }
                : body('GET /api/requests'),
          );
        }
        return Reply(
          reviewed
              ? body('PATCH /api/hr/requests/:id/review')
              : body('GET /api/hr/requests/:id'),
        );
      });
      final api = fakeApi(adapter);
      addTearDown(api.close);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            authControllerProvider.overrideWith(() => FixedAuth(hrUser())),
            apiClientProvider.overrideWithValue(api),
          ],
          child: const HrRequestApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Employment confirmation'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();
      expect(find.text('Approve this request?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
      await tester.pumpAndSettle();
      expect(
        adapter.requests.where((item) => item.method == 'PATCH'),
        hasLength(1),
      );
      await tester.drag(find.byType(ListView).last, const Offset(0, 800));
      await tester.pumpAndSettle();
      expect(find.text('Approved'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Approve'), findsNothing);
      expect(
        adapter.requests.firstWhere((item) => item.method == 'PATCH').data,
        {'status': 'APPROVED'},
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('No requests awaiting review.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('role guards send each user to their area without redirect loops', () {
    final employeeState = AuthState(AuthPhase.signedIn, user: employee());
    final hrState = AuthState(AuthPhase.signedIn, user: hrUser());
    expect(authRedirect(employeeState, '/login'), '/requests');
    expect(authRedirect(employeeState, '/hr/requests/123'), '/requests');
    expect(authRedirect(employeeState, '/requests'), isNull);
    expect(authRedirect(hrState, '/login'), '/hr/requests');
    expect(authRedirect(hrState, '/requests/new'), '/hr/requests');
    expect(authRedirect(hrState, '/hr/requests'), isNull);
    expect(
      authRedirect(const AuthState(AuthPhase.restoring), '/requests'),
      '/session',
    );
    expect(
      authRedirect(const AuthState(AuthPhase.restoring), '/session'),
      isNull,
    );
    expect(
      authRedirect(const AuthState(AuthPhase.recovery), '/login'),
      '/session',
    );
    expect(
      authRedirect(const AuthState(AuthPhase.signedOut), '/profile'),
      '/login',
    );
    expect(
      authRedirect(const AuthState(AuthPhase.signedOut), '/login'),
      isNull,
    );
  });
  test(
    'client validators match backend limits, trim and reject NUL characters',
    () {
      expect(validateEmail(' invalid '), isNotNull);
      expect(validateEmail(' alice@example.com '), isNull);
      expect(validatePassword(''), isNotNull);
      expect(validatePassword('é' * 37), isNotNull);
      expect(validateText('   ', label: 'Subject', max: 160), isNotNull);
      expect(validateText('a' * 161, label: 'Subject', max: 160), isNotNull);
      expect(
        validateText('a' * 5001, label: 'Description', max: 5000),
        isNotNull,
      );
      expect(
        validateText(
          'bad\u0000text',
          label: 'Comment',
          max: 2000,
          required: false,
        ),
        isNotNull,
      );
      expect(
        validateText('  ', label: 'Comment', max: 2000, required: false),
        isNull,
      );
    },
  );
  testWidgets(
    'login form requires valid email and password before submitting',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authControllerProvider.overrideWith(SignedOutAuth.new)],
          child: MaterialApp(theme: appTheme(), home: const LoginScreen()),
        ),
      );
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pump();
      expect(find.text('Email is required.'), findsOneWidget);
      expect(find.text('Password is required.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('login-email')), 'invalid');
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pump();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(find.byTooltip('Hide password'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('create form validates required type, subject and description', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => FixedAuth(employee())),
        ],
        child: MaterialApp(
          theme: appTheme(),
          home: const CreateRequestScreen(),
        ),
      ),
    );
    await tester.ensureVisible(find.byKey(const Key('request-submit')));
    await tester.tap(find.byKey(const Key('request-submit')));
    await tester.pump();
    expect(find.text('Request type is required.'), findsOneWidget);
    expect(find.text('Subject is required.'), findsOneWidget);
    expect(find.text('Description is required.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final hr in [false, true]) {
    testWidgets(
      '${hr ? 'HR' : 'employee'} app opens its actual guarded list and profile',
      (tester) async {
        final adapter = FakeAdapter(
          (options) async => Reply(
            options.path == 'me'
                ? {
                    'data': hr
                        ? {
                            'id': hrUser().id,
                            'employeeId': hrUser().employeeId,
                            'name': hrUser().name,
                            'email': hrUser().email,
                            'department': hrUser().department,
                            'jobTitle': hrUser().jobTitle,
                            'role': 'HR',
                          }
                        : body('GET /api/me')['data'],
                  }
                : {
                    'data': <Object?>[],
                    'pagination': {
                      'page': 1,
                      'pageSize': 20,
                      'total': 0,
                      'totalPages': 0,
                    },
                  },
          ),
        );
        final api = fakeApi(adapter);
        addTearDown(api.close);
        await tester.pumpWidget(
          ProviderScope(
            retry: (_, _) => null,
            overrides: [
              authControllerProvider.overrideWith(
                () => FixedAuth(hr ? hrUser() : employee()),
              ),
              apiClientProvider.overrideWithValue(api),
            ],
            child: const HrRequestApp(),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(hr ? 'Pending requests' : 'My requests'),
          findsWidgets,
        );
        expect(
          find.text(
            hr ? 'No requests awaiting review.' : 'No requests on this page.',
          ),
          findsOneWidget,
        );
        expect(adapter.requests.single.path, hr ? 'hr/requests' : 'requests');
        await tester.tap(find.text('Profile'));
        await tester.pumpAndSettle();
        expect(find.text('Employee ID'), findsOneWidget);
        expect(find.text('Department'), findsOneWidget);
        expect(find.text('Job title'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
