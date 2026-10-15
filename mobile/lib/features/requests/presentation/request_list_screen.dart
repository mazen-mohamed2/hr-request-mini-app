import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/async_content.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/hr_request.dart';
import '../data/request_providers.dart';

class RequestListScreen extends ConsumerWidget {
  const RequestListScreen({super.key, this.hr = false});
  final bool hr;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageProvider = hr ? hrPageProvider : employeePageProvider;
    final page = ref.watch(pageProvider);
    final provider = hr
        ? pendingRequestsProvider(page)
        : employeeRequestsProvider(page);
    final requests = ref.watch(provider);
    return Scaffold(
      floatingActionButton: hr
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.go('/requests/new'),
              icon: const Icon(Icons.add),
              label: const Text('New request'),
            ),
      body: requests.when(
        loading: () => const LoadingView(),
        error: (error, _) =>
            ErrorView(error: error, onRetry: () => ref.invalidate(provider)),
        data: (result) {
          final lastPage = result.pagination.totalPages == 0
              ? 1
              : result.pagination.totalPages;
          if (page > lastPage) {
            // Another HR reviewer may have removed the current pending page.
            // Defer the page change until after this build has finished.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted && ref.read(pageProvider) == page) {
                ref.read(pageProvider.notifier).goTo(lastPage);
              }
            });
            return const LoadingView(message: 'Refreshing requests…');
          }
          return RefreshIndicator(
            onRefresh: () async {
              try {
                await ref.refresh(provider.future).then<void>((_) {});
              } catch (_) {
                /* Provider displays the error. */
              }
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        hr ? 'Pending requests' : 'My requests',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh requests',
                      onPressed: () => ref.invalidate(provider),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${result.pagination.total} ${result.pagination.total == 1 ? 'request' : 'requests'}',
                ),
                const SizedBox(height: 16),
                if (result.items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 44),
                    child: Column(
                      children: [
                        const Icon(Icons.inbox_outlined, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          hr
                              ? 'No requests awaiting review.'
                              : 'No requests on this page.',
                        ),
                        if (!hr && page == 1)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('Create a request to get started.'),
                          ),
                      ],
                    ),
                  ),
                for (final item in result.items)
                  _RequestCard(item: item, hr: hr),
                if (result.pagination.totalPages > 1 || page > 1)
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: page > 1
                            ? () =>
                                  ref.read(pageProvider.notifier).goTo(page - 1)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('Previous'),
                      ),
                      Text(
                        'Page $page of ${result.pagination.totalPages == 0 ? 1 : result.pagination.totalPages}',
                      ),
                      TextButton(
                        onPressed:
                            page < result.pagination.totalPages && page < 10000
                            ? () =>
                                  ref.read(pageProvider.notifier).goTo(page + 1)
                            : null,
                        child: const Text('Next'),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.item, required this.hr});
  final HrRequest item;
  final bool hr;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => context.go(
        '${hr ? '/hr/requests' : '/requests'}/${Uri.encodeComponent(item.id)}',
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.type.label,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(item.status),
              ],
            ),
            Text(item.subject, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (hr && item.employee != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${item.employee!.name} · ${item.employee!.employeeId}',
                ),
              ),
            Text(
              'Submitted ${formatDate(item.submittedAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}
