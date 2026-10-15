import '../../../core/api/api_client.dart';
import '../../../core/api/json.dart';
import 'hr_request.dart';

class RequestRepository {
  RequestRepository(this._api);
  final ApiClient _api;

  Future<RequestPage> employeeList(int page) => _api.send(
    'requests',
    RequestPage.fromJson,
    query: {'page': page, 'pageSize': 20},
  );
  Future<HrRequest> employeeDetail(String id) => _api.send(
    'requests/${Uri.encodeComponent(id)}',
    (json) => HrRequest.fromJson(jsonObject(json['data'])),
  );
  Future<HrRequest> create(CreateRequestInput input) => _api.send(
    'requests',
    (json) => HrRequest.fromJson(jsonObject(json['data'])),
    method: 'POST',
    data: input.toJson(),
  );

  Future<RequestPage> pendingList(int page) => _api.send(
    'hr/requests',
    RequestPage.fromJson,
    query: {'status': 'PENDING', 'page': page, 'pageSize': 20},
  );
  Future<HrRequest> hrDetail(String id) => _api.send(
    'hr/requests/${Uri.encodeComponent(id)}',
    (json) => HrRequest.fromJson(jsonObject(json['data'])),
  );
  Future<HrRequest> review(String id, ReviewInput input) => _api.send(
    'hr/requests/${Uri.encodeComponent(id)}/review',
    (json) => HrRequest.fromJson(jsonObject(json['data'])),
    method: 'PATCH',
    data: input.toJson(),
  );
}
