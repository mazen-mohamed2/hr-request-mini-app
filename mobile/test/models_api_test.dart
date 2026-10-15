import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_request_mobile/core/api/api_exception.dart';
import 'package:hr_request_mobile/core/api/json.dart';
import 'package:hr_request_mobile/core/config/app_config.dart';
import 'package:hr_request_mobile/features/auth/data/auth_repository.dart';
import 'package:hr_request_mobile/features/requests/data/hr_request.dart';
import 'package:hr_request_mobile/features/requests/data/request_repository.dart';
import 'support/fakes.dart';

void main() {
  test('captured login and profile have the same safe user and role', () {
    final login = jsonObject(body('POST /api/auth/login')['user']);
    expect(login, body('GET /api/me')['data']);
    expect(employee().role.apiValue, 'EMPLOYEE');
    expect(hrUser().role.apiValue, 'HR');
  });
  test(
    'captured pending, create, list, HR list and detail responses parse',
    () {
      for (final route in [
        'POST /api/requests',
        'GET /api/requests/:id',
        'GET /api/hr/requests/:id',
      ]) {
        final item = HrRequest.fromJson(jsonObject(body(route)['data']));
        expect(item.status, RequestStatus.pending);
        expect(item.hrComment, isNull);
        expect(item.reviewedBy, isNull);
        expect(item.reviewer, isNull);
        expect(item.reviewedAt, isNull);
        expect(item.employee?.employeeId, 'EMP001');
        expect(item.submittedAt?.isUtc, isTrue);
      }
      final page = RequestPage.fromJson(body('GET /api/requests'));
      expect(page.items, hasLength(1));
      expect(page.pagination.pageSize, 20);
      expect(page.pagination.totalPages, 1);
      expect(
        RequestPage.fromJson(body('GET /api/hr/requests?status=PENDING')).items,
        hasLength(2),
      );
    },
  );
  test('review response parses comment, dates and reviewer', () {
    final item = HrRequest.fromJson(
      jsonObject(body('PATCH /api/hr/requests/:id/review')['data']),
    );
    expect(item.status, RequestStatus.approved);
    expect(item.hrComment, 'Letter will be prepared.');
    expect(item.reviewer?.name, 'Hana HR');
    expect(item.reviewedAt?.isUtc, isTrue);
  });
  test('malformed optional review values and dates are tolerated', () {
    final json = {
      ...jsonObject(body('GET /api/requests/:id')['data']),
      'hrComment': 12,
      'reviewedBy': <Object?>[],
      'reviewedAt': 'not-a-date',
      'submittedAt': false,
      'reviewer': {'id': 'incomplete'},
    };
    final item = HrRequest.fromJson(json);
    expect(item.hrComment, isNull);
    expect(item.reviewedBy, isNull);
    expect(item.reviewedAt, isNull);
    expect(item.reviewer, isNull);
    expect(item.submittedAt, isNull);
  });
  test('empty pagination is supported', () {
    final page = RequestPage.fromJson({
      'data': <Object?>[],
      'pagination': {'page': 1, 'pageSize': 20, 'total': 0, 'totalPages': 0},
    });
    expect(page.items, isEmpty);
    expect(page.pagination.totalPages, 0);
  });
  test('create and review payloads contain only permitted fields', () {
    expect(
      const CreateRequestInput(
        type: RequestType.other,
        subject: '  Hello ',
        description: ' Details ',
      ).toJson(),
      {'type': 'OTHER', 'subject': 'Hello', 'description': 'Details'},
    );
    expect(
      ReviewInput(status: RequestStatus.approved, comment: '   ').toJson(),
      {'status': 'APPROVED'},
    );
    expect(ReviewInput(status: RequestStatus.rejected).toJson(), {
      'status': 'REJECTED',
    });
    expect(
      ReviewInput(status: RequestStatus.approved, comment: ' Done ').toJson(),
      {'status': 'APPROVED', 'comment': 'Done'},
    );
    expect(
      () => ReviewInput(status: RequestStatus.pending),
      throwsArgumentError,
    );
  });
  for (final status in [400, 401, 403, 404, 409, 429, 500]) {
    test('maps HTTP $status without exposing internal text', () {
      final error = ApiException.fromDio(
        DioException(
          requestOptions: RequestOptions(),
          response: Response<Object?>(
            requestOptions: RequestOptions(),
            statusCode: status,
            data: {
              'error': {'code': 'EXAMPLE', 'message': 'private database stack'},
            },
          ),
        ),
      );
      expect(error.statusCode, status);
      expect(error.message, isNot(contains('private database')));
    });
  }
  test('maps network errors and backend validation field details', () {
    final network = ApiException.fromDio(
      DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.connectionError,
      ),
    );
    expect(network.message, contains('connection'));
    final validation = ApiException.fromDio(
      DioException(
        requestOptions: RequestOptions(),
        response: Response<Object?>(
          requestOptions: RequestOptions(),
          statusCode: 400,
          data: body('ERROR 400 invalid input'),
        ),
      ),
    );
    expect(validation.fields, ['subject']);
  });
  test(
    'Dio uses /api base path and attaches bearer centrally, excluding login',
    () async {
      final adapter = FakeAdapter(
        (options) async => Reply(
          options.path == 'auth/login'
              ? body('POST /api/auth/login')
              : body('GET /api/me'),
        ),
      );
      final api = fakeApi(adapter)..token = 'unit-test-token';
      addTearDown(api.close);
      final auth = AuthRepository(api);
      await auth.login(' ALICE@example.com ', 'sample-password');
      await auth.me();
      expect(adapter.requests[0].uri.path, '/api/auth/login');
      expect(adapter.requests[0].headers.containsKey('Authorization'), isFalse);
      expect(adapter.requests[0].data, {
        'email': 'alice@example.com',
        'password': 'sample-password',
      });
      expect(
        adapter.requests[1].headers['Authorization'],
        'Bearer unit-test-token',
      );
    },
  );
  test(
    'repositories use actual list, create, detail and HR review contracts',
    () async {
      final adapter = FakeAdapter((options) async {
        if (options.method == 'PATCH') {
          return Reply(body('PATCH /api/hr/requests/:id/review'));
        }
        if (options.method == 'POST') {
          return Reply(body('POST /api/requests'), 201);
        }
        if (options.path == 'hr/requests') {
          return Reply(body('GET /api/hr/requests?status=PENDING'));
        }
        if (options.path == 'requests') return Reply(body('GET /api/requests'));
        return Reply(body('GET /api/requests/:id'));
      });
      final api = fakeApi(adapter);
      addTearDown(api.close);
      final repository = RequestRepository(api);
      expect((await repository.employeeList(2)).items, hasLength(1));
      expect(adapter.requests.last.queryParameters, {
        'page': 2,
        'pageSize': 20,
      });
      await repository.pendingList(1);
      expect(adapter.requests.last.queryParameters['status'], 'PENDING');
      await repository.employeeDetail('request-id');
      await repository.hrDetail('request-id');
      await repository.create(
        const CreateRequestInput(
          type: RequestType.other,
          subject: 'Hi',
          description: 'Details',
        ),
      );
      expect(adapter.requests.last.data, {
        'type': 'OTHER',
        'subject': 'Hi',
        'description': 'Details',
      });
      await repository.review(
        'request-id',
        ReviewInput(status: RequestStatus.approved, comment: ' '),
      );
      expect(adapter.requests.last.path, 'hr/requests/request-id/review');
      expect(adapter.requests.last.data, {'status': 'APPROVED'});
    },
  );
  test('malformed required response is mapped to a safe API error', () async {
    final api = fakeApi(FakeAdapter((_) async => const Reply({'data': 'bad'})));
    addTearDown(api.close);
    await expectLater(
      AuthRepository(api).me(),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE'),
      ),
    );
  });
  test(
    'base URL is centralized and normalized without embedded credentials',
    () {
      expect(
        AppConfig(apiBaseUrl: 'https://example.test/api///').apiBaseUrl,
        'https://example.test/api/',
      );
      expect(
        () => AppConfig(apiBaseUrl: 'https://user:secret@example.test/api'),
        throwsArgumentError,
      );
    },
  );
}
