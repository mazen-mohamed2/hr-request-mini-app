import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_request_mobile/app.dart';
import 'package:hr_request_mobile/core/auth/auth_controller.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('session recovery stays usable in landscape with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    var attempts = 0;
    final storage = MemoryTokenStorage('saved-session');
    final api = fakeApi(
      FakeAdapter((options) async {
        if (options.path == 'me') {
          attempts++;
          return attempts == 1
              ? const Reply({
                  'error': {'code': 'UNAVAILABLE'},
                }, 503)
              : Reply(body('GET /api/me'));
        }
        return const Reply({
          'data': <Object?>[],
          'pagination': {
            'page': 1,
            'pageSize': 20,
            'total': 0,
            'totalPages': 0,
          },
        });
      }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStorageProvider.overrideWithValue(storage),
        ],
        child: const HrRequestApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Sign out'));
    await tester.ensureVisible(find.text('Try again'));
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(storage.value, 'saved-session');
    expect(find.text('My requests'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('landscape list errors remain reachable and can be retried', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var attempts = 0;
    final api = fakeApi(
      FakeAdapter((_) async {
        attempts++;
        return attempts == 1
            ? const Reply({
                'error': {'code': 'INTERNAL_ERROR'},
              }, 500)
            : const Reply({
                'data': <Object?>[],
                'pagination': {
                  'page': 1,
                  'pageSize': 20,
                  'total': 0,
                  'totalPages': 0,
                },
              });
      }),
    );
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
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Try again'));
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('No requests on this page.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pagination remains usable on a narrow phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final template =
        body('GET /api/requests/:id')['data'] as Map<String, dynamic>;
    final adapter = FakeAdapter((options) async {
      final page = options.queryParameters['page'] as int;
      return Reply({
        'data': [
          for (
            var index = (page - 1) * 20;
            index < (page == 1 ? 20 : 21);
            index++
          )
            {
              ...template,
              'id':
                  '00000000-0000-4000-8000-${(index + 1).toString().padLeft(12, '0')}',
              'subject': 'Request ${index + 1}',
            },
        ],
        'pagination': {
          'page': page,
          'pageSize': 20,
          'total': 21,
          'totalPages': 2,
        },
      });
    });
    final api = fakeApi(adapter);
    addTearDown(api.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => FixedAuth(employee())),
          apiClientProvider.overrideWithValue(api),
        ],
        child: const HrRequestApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Next'), 500, maxScrolls: 50);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(adapter.requests.last.queryParameters['page'], 2);
    expect(find.text('Request 21'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
