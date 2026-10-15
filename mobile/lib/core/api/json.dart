typedef Json = Map<String, dynamic>;

Json jsonObject(Object? value) {
  if (value is Map<String, dynamic>) return value;
  throw const FormatException('Expected a JSON object.');
}

String requiredString(Json json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Missing required field: $key');
}

String? optionalString(Object? value) => value is String ? value : null;
DateTime? optionalDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
