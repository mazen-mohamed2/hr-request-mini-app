import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_request_mobile/core/auth/auth_controller.dart';
import 'package:hr_request_mobile/features/requests/data/hr_request.dart';
import 'package:hr_request_mobile/features/requests/data/request_providers.dart';
import 'support/fakes.dart';

void main() {
  test(
    'a create completing after sign-out cannot publish the previous session result',
    () async {
      final delayed = Completer<Reply>();
      final api = fakeApi(FakeAdapter((_) => delayed.future));
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          apiClientProvider.overrideWithValue(api),
          authControllerProvider.overrideWith(SwitchingAuth.new),
        ],
      );
      addTearDown(() {
        container.dispose();
        api.close();
      });
      final subscription = container.listen(createRequestProvider, (_, _) {});
      addTearDown(subscription.close);
      final result = container
          .read(createRequestProvider.notifier)
          .submit(
            const CreateRequestInput(
              type: RequestType.other,
              subject: 'Old request',
              description: 'Old session',
            ),
          );
      (container.read(authControllerProvider.notifier) as SwitchingAuth)
          .signOut();
      delayed.complete(Reply(body('POST /api/requests'), 201));
      expect(await result, isNull);
      expect(container.read(createRequestProvider).asData?.value, isNull);
    },
  );
  ProviderContainer setup(FakeAdapter adapter, {bool hr = false}) {
    final api = fakeApi(adapter);
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        apiClientProvider.overrideWithValue(api),
        authControllerProvider.overrideWith(
          () => FixedAuth(hr ? hrUser() : employee()),
        ),
      ],
    );
    addTearDown(() {
      container.dispose();
      api.close();
    });
    return container;
  }

  const input = CreateRequestInput(
    type: RequestType.other,
    subject: 'New subject',
    description: 'New description',
  );

  test(
    'successful create resets pagination and refreshes the employee list',
    () async {
      var created = false;
      final adapter = FakeAdapter((options) async {
        if (options.method == 'POST') {
          created = true;
          return Reply(body('POST /api/requests'), 201);
        }
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
      });
      final container = setup(adapter);
      final list = container.listen(employeeRequestsProvider(1), (_, _) {});
      final action = container.listen(createRequestProvider, (_, _) {});
      addTearDown(list.close);
      addTearDown(action.close);
      expect(
        (await container.read(employeeRequestsProvider(1).future)).items,
        isEmpty,
      );
      container.read(employeePageProvider.notifier).goTo(3);
      final result = await container
          .read(createRequestProvider.notifier)
          .submit(input);
      expect(result?.status, RequestStatus.pending);
      expect(container.read(employeePageProvider), 1);
      expect(
        (await container.read(employeeRequestsProvider(1).future)).items,
        hasLength(1),
      );
      expect(
        adapter.requests.where((item) => item.method == 'POST'),
        hasLength(1),
      );
    },
  );
  test(
    'create action blocks duplicate submissions while request is in flight',
    () async {
      final delayed = Completer<Reply>();
      final adapter = FakeAdapter((_) => delayed.future);
      final container = setup(adapter);
      final subscription = container.listen(createRequestProvider, (_, _) {});
      addTearDown(subscription.close);
      final controller = container.read(createRequestProvider.notifier);
      final first = controller.submit(input);
      expect(await controller.submit(input), isNull);
      delayed.complete(Reply(body('POST /api/requests'), 201));
      expect(await first, isNotNull);
      expect(adapter.requests, hasLength(1));
    },
  );
  test(
    'review persists blank-comment payload and refreshes pending list/detail',
    () async {
      var reviewed = false;
      final pending = body('GET /api/requests/:id');
      final approved = body('PATCH /api/hr/requests/:id/review');
      final adapter = FakeAdapter((options) async {
        if (options.method == 'PATCH') {
          reviewed = true;
          return Reply(approved);
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
        return Reply(reviewed ? approved : pending);
      });
      final container = setup(adapter, hr: true);
      final id = (pending['data'] as Map<String, dynamic>)['id'] as String;
      final list = container.listen(pendingRequestsProvider(1), (_, _) {});
      final detail = container.listen(hrDetailProvider(id), (_, _) {});
      final action = container.listen(reviewRequestProvider(id), (_, _) {});
      addTearDown(list.close);
      addTearDown(detail.close);
      addTearDown(action.close);
      expect(
        (await container.read(pendingRequestsProvider(1).future)).items,
        hasLength(1),
      );
      expect(
        (await container.read(hrDetailProvider(id).future)).status,
        RequestStatus.pending,
      );
      final result = await container
          .read(reviewRequestProvider(id).notifier)
          .submit(ReviewInput(status: RequestStatus.approved, comment: '  '));
      expect(result?.status, RequestStatus.approved);
      expect(
        adapter.requests.firstWhere((item) => item.method == 'PATCH').data,
        {'status': 'APPROVED'},
      );
      expect(
        (await container.read(pendingRequestsProvider(1).future)).items,
        isEmpty,
      );
      expect(
        (await container.read(hrDetailProvider(id).future)).status,
        RequestStatus.approved,
      );
    },
  );
  test(
    '409 exposes a useful conflict and reloads the already-reviewed state',
    () async {
      var reviewed = false;
      final pending = body('GET /api/requests/:id');
      final adapter = FakeAdapter((options) async {
        if (options.method == 'PATCH') {
          reviewed = true;
          return Reply(body('ERROR 409 repeated review'), 409);
        }
        if (options.path == 'hr/requests') {
          return Reply({
            'data': <Object?>[],
            'pagination': {
              'page': 1,
              'pageSize': 20,
              'total': 0,
              'totalPages': 0,
            },
          });
        }
        return Reply(
          reviewed ? body('PATCH /api/hr/requests/:id/review') : pending,
        );
      });
      final container = setup(adapter, hr: true);
      final id = (pending['data'] as Map<String, dynamic>)['id'] as String;
      final detail = container.listen(hrDetailProvider(id), (_, _) {});
      final action = container.listen(reviewRequestProvider(id), (_, _) {});
      addTearDown(detail.close);
      addTearDown(action.close);
      await container.read(hrDetailProvider(id).future);
      expect(
        await container
            .read(reviewRequestProvider(id).notifier)
            .submit(ReviewInput(status: RequestStatus.rejected)),
        isNull,
      );
      expect(container.read(reviewRequestProvider(id)).hasError, isTrue);
      expect(
        container.read(reviewRequestProvider(id)).error.toString(),
        contains('already been reviewed'),
      );
      expect(
        (await container.read(hrDetailProvider(id).future)).status,
        RequestStatus.approved,
      );
    },
  );
}
