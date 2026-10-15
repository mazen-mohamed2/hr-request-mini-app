import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/widgets/async_content.dart';

class SessionScreen extends ConsumerWidget {
  const SessionScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: auth.phase == AuthPhase.recovery
            ? Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ErrorView(
                        error: auth.error!,
                        onRetry: () =>
                            ref.read(authControllerProvider.notifier).restore(),
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.read(authControllerProvider.notifier).logout(),
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                ),
              )
            : const LoadingView(message: 'Restoring your session…'),
      ),
    );
  }
}
