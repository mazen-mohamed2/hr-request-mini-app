import 'dart:convert';

String? validateEmail(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return 'Email is required.';
  if (email.length > 254 ||
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
    return 'Enter a valid email address.';
  }
  return null;
}

String? validatePassword(String? value) {
  if (value == null || value.isEmpty) return 'Password is required.';
  if (utf8.encode(value).length > 72) return 'Password is too long.';
  return null;
}

String? validateText(
  String? value, {
  required String label,
  required int max,
  bool required = true,
}) {
  final text = value?.trim() ?? '';
  if (required && text.isEmpty) return '$label is required.';
  if (text.length > max) return '$label must be $max characters or fewer.';
  if (text.contains('\u0000')) {
    return '$label contains an unsupported character.';
  }
  return null;
}
