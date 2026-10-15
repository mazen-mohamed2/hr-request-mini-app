import '../../../core/api/json.dart';
import '../../profile/data/user_profile.dart';

enum RequestType {
  employmentLetter('EMPLOYMENT_LETTER', 'Employment Letter'),
  salaryCertificate('SALARY_CERTIFICATE', 'Salary Certificate'),
  personalInformationChange(
    'PERSONAL_INFORMATION_CHANGE',
    'Personal Information Change',
  ),
  other('OTHER', 'Other');

  const RequestType(this.apiValue, this.label);
  final String apiValue, label;
  static RequestType parse(Object? value) => values.firstWhere(
    (item) => item.apiValue == value,
    orElse: () => throw const FormatException('Unsupported request type.'),
  );
}

enum RequestStatus {
  pending('PENDING', 'Pending'),
  approved('APPROVED', 'Approved'),
  rejected('REJECTED', 'Rejected');

  const RequestStatus(this.apiValue, this.label);
  final String apiValue, label;
  static RequestStatus parse(Object? value) => values.firstWhere(
    (item) => item.apiValue == value,
    orElse: () => throw const FormatException('Unsupported request status.'),
  );
}

UserProfile? _optionalUser(Object? value) {
  if (value is! Map<String, dynamic>) return null;
  try {
    return UserProfile.fromJson(value);
  } on FormatException {
    return null;
  }
}

class HrRequest {
  const HrRequest({
    required this.id,
    required this.employeeId,
    required this.type,
    required this.subject,
    required this.description,
    required this.status,
    this.hrComment,
    this.reviewedBy,
    this.submittedAt,
    this.reviewedAt,
    this.createdAt,
    this.updatedAt,
    this.employee,
    this.reviewer,
  });

  factory HrRequest.fromJson(Json json) => HrRequest(
    id: requiredString(json, 'id'),
    employeeId: requiredString(json, 'employeeId'),
    type: RequestType.parse(json['type']),
    subject: requiredString(json, 'subject'),
    description: requiredString(json, 'description'),
    status: RequestStatus.parse(json['status']),
    hrComment: optionalString(json['hrComment']),
    reviewedBy: optionalString(json['reviewedBy']),
    submittedAt: optionalDate(json['submittedAt']),
    reviewedAt: optionalDate(json['reviewedAt']),
    createdAt: optionalDate(json['createdAt']),
    updatedAt: optionalDate(json['updatedAt']),
    employee: _optionalUser(json['employee']),
    reviewer: _optionalUser(json['reviewer']),
  );
  final String id, employeeId, subject, description;
  final RequestType type;
  final RequestStatus status;
  final String? hrComment, reviewedBy;
  final DateTime? submittedAt, reviewedAt, createdAt, updatedAt;
  final UserProfile? employee, reviewer;
}

class Pagination {
  const Pagination({
    required this.page,
    required this.pageSize,
    required this.total,
    required this.totalPages,
  });
  factory Pagination.fromJson(Json json) {
    int read(String key, int minimum) {
      final value = json[key];
      if (value is! int || value < minimum) {
        throw const FormatException('Invalid pagination.');
      }
      return value;
    }

    return Pagination(
      page: read('page', 1),
      pageSize: read('pageSize', 1),
      total: read('total', 0),
      totalPages: read('totalPages', 0),
    );
  }
  final int page, pageSize, total, totalPages;
}

class RequestPage {
  const RequestPage(this.items, this.pagination);
  factory RequestPage.fromJson(Json json) {
    final data = json['data'];
    if (data is! List) throw const FormatException('Invalid request list.');
    return RequestPage(
      List.unmodifiable(
        data.map((item) => HrRequest.fromJson(jsonObject(item))),
      ),
      Pagination.fromJson(jsonObject(json['pagination'])),
    );
  }
  final List<HrRequest> items;
  final Pagination pagination;
}

class CreateRequestInput {
  const CreateRequestInput({
    required this.type,
    required this.subject,
    required this.description,
  });
  final RequestType type;
  final String subject, description;
  Json toJson() => {
    'type': type.apiValue,
    'subject': subject.trim(),
    'description': description.trim(),
  };
}

class ReviewInput {
  ReviewInput({required this.status, this.comment}) {
    if (status == RequestStatus.pending) {
      throw ArgumentError('Review must approve or reject.');
    }
  }
  final RequestStatus status;
  final String? comment;
  Json toJson() => {
    'status': status.apiValue,
    if (comment != null && comment!.trim().isNotEmpty)
      'comment': comment!.trim(),
  };
}
