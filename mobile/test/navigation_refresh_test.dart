import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_request_mobile/app.dart';
import 'package:hr_request_mobile/core/auth/auth_controller.dart';
import 'package:hr_request_mobile/core/auth/auth_state.dart';
import 'package:hr_request_mobile/core/router/app_router.dart';
import 'package:hr_request_mobile/features/requests/data/request_providers.dart';
import 'support/fakes.dart';

void main() {
  testWidgets(
    'refresh recovers when another HR review removes the last pending page',
    (tester) async {
      var remaining = 21;
      final template =
          body('GET /api/requests/:id')['data'] as Map<String, dynamic>;
      final adapter = FakeAdapter((options) async {
        final page = options.queryParameters['page'] as int;
        final start = (page - 1) * 20;
        final end = (start + 20).clamp(0, remaining);
        return Reply({
          'data': [
            for (var index = start; index < end; index++)
              {
                ...template,
                'id':
                    '00000000-0000-4000-8000-${(index + 1).toString().padLeft(12, '0')}',
                'subject': 'Pending request ${index + 1}',
              },
          ],
          'pagination': {
            'page': page,
            'pageSize': 20,
            'total': remaining,
            'totalPages': (remaining / 20).ceil(),
          },
        });
      });
      final api = fakeApi(adapter);
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          apiClientProvider.overrideWithValue(api),
          authControllerProvider.overrideWith(() => FixedAuth(hrUser())),
        ],
      );
      addTearDown(() {
        container.dispose();
        api.close();
      });
      container.read(hrPageProvider.notifier).goTo(2);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const HrRequestApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pending request 21'), findsOneWidget);
      remaining = 20;
      await tester.tap(find.byTooltip('Refresh requests'));
      await tester.pumpAndSettle();
      expect(container.read(hrPageProvider), 1);
      expect(find.text('Pending request 1'), findsOneWidget);
      expect(find.text('Page 2 of 1'), findsNothing);
      expect(find.text('No requests awaiting review.'), findsNothing);
      expect(adapter.requests.last.queryParameters['page'], 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'a late successful restore cannot authenticate after explicit logout',
    () async {
      final started = Completer<void>();
      final response = Completer<Reply>();
      final storage = MemoryTokenStorage('saved-session');
      final adapter = FakeAdapter((_) {
        started.complete();
        return response.future;
      });
      final container = authContainer(adapter, storage);
      addTearDown(container.dispose);
      container.read(authControllerProvider);
      await started.future;
      await container.read(authControllerProvider.notifier).logout();
      response.complete(Reply(body('GET /api/me')));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(authControllerProvider).phase, AuthPhase.signedOut);
      expect(container.read(authControllerProvider).user, isNull);
      expect(container.read(apiClientProvider).token, isNull);
      expect(storage.value, isNull);
      expect(storage.clears, 1);
    },
  );

  for (final hr in [false, true]) {
    testWidgets(
      '${hr ? 'HR' : 'employee'} manual routes stay guarded and logout removes protected history',
      (tester) async {
        final adapter = FakeAdapter(
          (options) async => Reply(
            options.path.endsWith('/item')
                ? body('GET /api/requests/:id')
                : body('GET /api/requests'),
          ),
        );
        final api = fakeApi(adapter)..token = 'test-session';
        final storage = MemoryTokenStorage('test-session');
        final container = ProviderContainer(
          retry: (_, _) => null,
          overrides: [
            apiClientProvider.overrideWithValue(api),
            tokenStorageProvider.overrideWithValue(storage),
            authControllerProvider.overrideWith(
              () => FixedAuth(hr ? hrUser() : employee()),
            ),
          ],
        );
        addTearDown(() {
          container.dispose();
          api.close();
        });
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const HrRequestApp(),
          ),
        );
        await tester.pumpAndSettle();
        final router = container.read(appRouterProvider);
        router.go(hr ? '/requests/new' : '/hr/requests/item');
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          hr ? '/hr/requests' : '/requests',
        );
        unawaited(
          router.push<void>(hr ? '/hr/requests/item' : '/requests/item'),
        );
        await tester.pumpAndSettle();
        expect(router.canPop(), isTrue);
        await container.read(authControllerProvider.notifier).logout();
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/login');
        expect(router.canPop(), isFalse);
        expect(storage.value, isNull);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('login-submit')), findsOneWidget);
        expect(find.text('Request details'), findsNothing);
        router.go(hr ? '/hr/requests/item' : '/requests/item');
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/login');
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
