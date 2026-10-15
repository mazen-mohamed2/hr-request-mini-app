import 'package:flutter/material.dart';

ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff245a66)),
  scaffoldBackgroundColor: const Color(0xfff6f8fa),
  appBarTheme: const AppBarTheme(centerTitle: false),
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
  ),
);
