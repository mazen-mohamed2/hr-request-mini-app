import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/session_screen.dart';
import '../../features/profile/data/user_profile.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/requests/presentation/create_request_screen.dart';
import '../../features/requests/presentation/request_detail_screen.dart';
import '../../features/requests/presentation/request_list_screen.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_state.dart';
import '../widgets/app_shell.dart';

String? authRedirect(AuthState auth, String location) {
  if (auth.phase == AuthPhase.restoring || auth.phase == AuthPhase.recovery) {
    return location == '/session' ? null : '/session';
  }
  if (auth.phase == AuthPhase.signedOut) {
    return location == '/login' ? null : '/login';
  }
  final home = auth.user?.role == UserRole.hr ? '/hr/requests' : '/requests';
  if (location == '/session' || location == '/login' || location == '/') {
    return home;
  }
  if (auth.user?.role == UserRole.employee && location.startsWith('/hr')) {
    return home;
  }
  if (auth.user?.role == UserRole.hr && location.startsWith('/requests')) {
    return home;
  }
  return null;
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh();
  ref.listen(authControllerProvider, (_, _) => refresh.changed());
  final router = GoRouter(
    initialLocation: '/session',
    refreshListenable: refresh,
    redirect: (context, state) =>
        authRedirect(ref.read(authControllerProvider), state.uri.path),
    routes: [
      GoRoute(
        path: '/session',
        builder: (context, state) => const SessionScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: '/requests',
            builder: (context, state) => const RequestListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const CreateRequestScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    RequestDetailScreen(id: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/hr/requests',
            builder: (context, state) => const RequestListScreen(hr: true),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) => RequestDetailScreen(
                  id: state.pathParameters['id']!,
                  hr: true,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Page unavailable')),
      body: Center(
        child: FilledButton(
          onPressed: () => context.go('/'),
          child: const Text('Go to requests'),
        ),
      ),
    ),
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

class _RouterRefresh extends ChangeNotifier {
  void changed() => notifyListeners();
}
