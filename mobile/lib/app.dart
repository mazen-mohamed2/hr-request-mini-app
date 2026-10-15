import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class HrRequestApp extends ConsumerWidget {
  const HrRequestApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'HR Requests',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    routerConfig: ref.watch(appRouterProvider),
  );
}
