import '../../../core/api/json.dart';

enum UserRole {
  employee('EMPLOYEE'),
  hr('HR');

  const UserRole(this.apiValue);
  final String apiValue;
  static UserRole parse(Object? value) => switch (value) {
    'EMPLOYEE' => employee,
    'HR' => hr,
    _ => throw const FormatException('Unsupported user role.'),
  };
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.employeeId,
    required this.name,
    required this.email,
    required this.department,
    required this.jobTitle,
    required this.role,
    this.createdAt,
    this.updatedAt,
  });

  factory UserProfile.fromJson(Json json) => UserProfile(
    id: requiredString(json, 'id'),
    employeeId: requiredString(json, 'employeeId'),
    name: requiredString(json, 'name'),
    email: requiredString(json, 'email'),
    department: requiredString(json, 'department'),
    jobTitle: requiredString(json, 'jobTitle'),
    role: UserRole.parse(json['role']),
    createdAt: optionalDate(json['createdAt']),
    updatedAt: optionalDate(json['updatedAt']),
  );

  final String id, employeeId, name, email, department, jobTitle;
  final UserRole role;
  final DateTime? createdAt, updatedAt;
}
