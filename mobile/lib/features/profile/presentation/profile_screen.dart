import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/async_content.dart';
import '../data/profile_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    return profile.when(
      loading: () => const LoadingView(),
      error: (error, _) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(profileProvider),
      ),
      data: (user) => RefreshIndicator(
        onRefresh: () async {
          try {
            await ref.refresh(profileProvider.future).then<void>((_) {});
          } catch (_) {
            /* Error is displayed by the provider. */
          }
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Your profile',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            Card(
              child: Column(
                children: [
                  _field(Icons.person_outline, 'Name', user.name),
                  _field(Icons.badge_outlined, 'Employee ID', user.employeeId),
                  _field(
                    Icons.business_outlined,
                    'Department',
                    user.department,
                  ),
                  _field(Icons.work_outline, 'Job title', user.jobTitle),
                  _field(Icons.mail_outline, 'Email', user.email),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(IconData icon, String title, String value) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: SelectableText(value),
  );
}
