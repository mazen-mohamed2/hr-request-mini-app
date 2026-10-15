import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/auth/auth_controller.dart';
import 'hr_request.dart';
import 'request_repository.dart';

final requestRepositoryProvider = Provider<RequestRepository>(
  (ref) => RequestRepository(ref.watch(apiClientProvider)),
);

void _requireSession(Ref ref) {
  final userId = ref.watch(
    authControllerProvider.select((state) => state.user?.id),
  );
  if (userId == null) {
    throw const ApiException('UNAUTHORIZED', 'Please sign in again.');
  }
}

final employeeRequestsProvider = FutureProvider.autoDispose
    .family<RequestPage, int>((ref, page) {
      _requireSession(ref);
      return ref.watch(requestRepositoryProvider).employeeList(page);
    });
final pendingRequestsProvider = FutureProvider.autoDispose
    .family<RequestPage, int>((ref, page) {
      _requireSession(ref);
      return ref.watch(requestRepositoryProvider).pendingList(page);
    });
final employeeDetailProvider = FutureProvider.autoDispose
    .family<HrRequest, String>((ref, id) {
      _requireSession(ref);
      return ref.watch(requestRepositoryProvider).employeeDetail(id);
    });
final hrDetailProvider = FutureProvider.autoDispose.family<HrRequest, String>((
  ref,
  id,
) {
  _requireSession(ref);
  return ref.watch(requestRepositoryProvider).hrDetail(id);
});

class RequestPageController extends Notifier<int> {
  @override
  int build() {
    ref.watch(authControllerProvider.select((state) => state.user?.id));
    return 1;
  }

  void goTo(int page) {
    if (page >= 1 && page <= 10000) state = page;
  }
}

final employeePageProvider = NotifierProvider<RequestPageController, int>(
  RequestPageController.new,
);
final hrPageProvider = NotifierProvider<RequestPageController, int>(
  RequestPageController.new,
);

final createRequestProvider =
    AsyncNotifierProvider.autoDispose<CreateRequestController, HrRequest?>(
      CreateRequestController.new,
    );

class CreateRequestController extends AsyncNotifier<HrRequest?> {
  int _operation = 0;
  @override
  HrRequest? build() {
    ref.watch(authControllerProvider.select((state) => state.user?.id));
    _operation++;
    return null;
  }

  Future<HrRequest?> submit(CreateRequestInput input) async {
    if (state.isLoading) return null;
    final operation = ++_operation;
    final userId = ref.read(authControllerProvider).user?.id;
    if (userId == null) return null;
    state = const AsyncLoading();
    try {
      final created = await ref.read(requestRepositoryProvider).create(input);
      if (!ref.mounted ||
          operation != _operation ||
          ref.read(authControllerProvider).user?.id != userId) {
        return null;
      }
      ref.read(employeePageProvider.notifier).goTo(1);
      ref.invalidate(employeeRequestsProvider);
      state = AsyncData(created);
      return created;
    } catch (error, stack) {
      if (ref.mounted &&
          operation == _operation &&
          ref.read(authControllerProvider).user?.id == userId) {
        state = AsyncError(ApiException.from(error), stack);
      }
      return null;
    }
  }
}

final reviewRequestProvider = AsyncNotifierProvider.autoDispose
    .family<ReviewRequestController, HrRequest?, String>(
      ReviewRequestController.new,
    );

class ReviewRequestController extends AsyncNotifier<HrRequest?> {
  ReviewRequestController(this.id);
  final String id;
  int _operation = 0;
  @override
  HrRequest? build() {
    ref.watch(authControllerProvider.select((state) => state.user?.id));
    _operation++;
    return null;
  }

  Future<HrRequest?> submit(ReviewInput input) async {
    if (state.isLoading) return null;
    final operation = ++_operation;
    final userId = ref.read(authControllerProvider).user?.id;
    if (userId == null) return null;
    state = const AsyncLoading();
    try {
      final reviewed = await ref
          .read(requestRepositoryProvider)
          .review(id, input);
      if (!ref.mounted ||
          operation != _operation ||
          ref.read(authControllerProvider).user?.id != userId) {
        return null;
      }
      ref.read(hrPageProvider.notifier).goTo(1);
      ref.invalidate(pendingRequestsProvider);
      ref.invalidate(hrDetailProvider(id));
      state = AsyncData(reviewed);
      return reviewed;
    } catch (error, stack) {
      if (!ref.mounted ||
          operation != _operation ||
          ref.read(authControllerProvider).user?.id != userId) {
        return null;
      }
      final failure = ApiException.from(error);
      if (failure.statusCode == 409) {
        ref.read(hrPageProvider.notifier).goTo(1);
        ref.invalidate(pendingRequestsProvider);
        ref.invalidate(hrDetailProvider(id));
      }
      state = AsyncError(failure, stack);
      return null;
    }
  }
}
