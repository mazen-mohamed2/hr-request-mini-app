import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/auth/auth_controller.dart';
import 'user_profile.dart';

final profileProvider = FutureProvider.autoDispose<UserProfile>((ref) {
  final userId = ref.watch(
    authControllerProvider.select((state) => state.user?.id),
  );
  if (userId == null) {
    throw const ApiException('UNAUTHORIZED', 'Please sign in again.');
  }
  return ref.watch(authRepositoryProvider).me();
});
