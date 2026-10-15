import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/async_content.dart';
import '../../../core/widgets/status_chip.dart';
import '../../hr/presentation/review_panel.dart';
import '../data/hr_request.dart';
import '../data/request_providers.dart';

class RequestDetailScreen extends ConsumerWidget {
  const RequestDetailScreen({super.key, required this.id, this.hr = false});
  final String id;
  final bool hr;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = hr ? hrDetailProvider(id) : employeeDetailProvider(id);
    final request = ref.watch(provider);
    final review = hr ? ref.watch(reviewRequestProvider(id)) : null;
    return PopScope(
      canPop: review?.isLoading != true,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Request details'),
          actions: [
            IconButton(
              tooltip: 'Refresh request',
              onPressed: review?.isLoading == true
                  ? null
                  : () => ref.invalidate(provider),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: request.when(
          loading: () => const LoadingView(),
          error: (error, _) =>
              ErrorView(error: error, onRetry: () => ref.invalidate(provider)),
          data: (fetched) {
            final item = review?.asData?.value ?? fetched;
            return RefreshIndicator(
              onRefresh: () async {
                if (review?.isLoading == true) return;
                try {
                  await ref.refresh(provider.future).then<void>((_) {});
                } catch (_) {
                  /* Provider displays the error. */
                }
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: StatusChip(item.status),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.subject,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.type.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 24),
                  if (hr && item.employee != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.employee!.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(item.employee!.employeeId),
                            Text(
                              '${item.employee!.department} · ${item.employee!.jobTitle}',
                            ),
                            Text(item.employee!.email),
                          ],
                        ),
                      ),
                    ),
                  _section(context, 'Description', item.description),
                  _section(
                    context,
                    'Submitted',
                    formatDate(item.submittedAt, includeTime: true),
                  ),
                  if (item.hrComment != null &&
                      item.hrComment!.trim().isNotEmpty)
                    _section(context, 'HR comment', item.hrComment!),
                  if (item.reviewedAt != null)
                    _section(
                      context,
                      'Reviewed',
                      formatDate(item.reviewedAt, includeTime: true),
                    ),
                  if (item.reviewer != null)
                    _section(context, 'Reviewed by', item.reviewer!.name),
                  if (hr &&
                      review?.hasError == true &&
                      item.status != RequestStatus.pending)
                    ErrorMessage(review!.error!),
                  if (hr && item.status == RequestStatus.pending) ...[
                    const Divider(height: 32),
                    ReviewPanel(requestId: id),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        SelectableText(value),
      ],
    ),
  );
}
