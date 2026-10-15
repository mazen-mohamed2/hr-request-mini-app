import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/profile/data/user_profile.dart';
import '../auth/auth_controller.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child, required this.location});
  final Widget child;
  final String location;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(
      authControllerProvider.select((state) => state.user),
    );
    final hr = user?.role == UserRole.hr;
    final mainPage = const [
      '/requests',
      '/hr/requests',
      '/profile',
    ].contains(location);
    return Scaffold(
      appBar: !mainPage
          ? null
          : AppBar(
              title: Text(hr ? 'HR Review' : 'HR Requests'),
              actions: [
                IconButton(
                  tooltip: 'Sign out',
                  icon: const Icon(Icons.logout),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Sign out?'),
                        content: const Text(
                          'You can sign in again with your work account.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Sign out'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted) {
                      await ref.read(authControllerProvider.notifier).logout();
                    }
                  },
                ),
              ],
            ),
      body: child,
      bottomNavigationBar: !mainPage
          ? null
          : NavigationBar(
              selectedIndex: location.startsWith('/profile') ? 1 : 0,
              onDestinationSelected: (index) => context.go(
                index == 1
                    ? '/profile'
                    : hr
                    ? '/hr/requests'
                    : '/requests',
              ),
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.description_outlined),
                  selectedIcon: const Icon(Icons.description),
                  label: hr ? 'Pending' : 'My requests',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            ),
    );
  }
}
