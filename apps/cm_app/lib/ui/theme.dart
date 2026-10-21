import 'package:flutter/material.dart';

const _seed = Color(0xFF1B5E20);

ThemeData lightTheme() => _theme(Brightness.light);

ThemeData darkTheme() => _theme(Brightness.dark);

ThemeData _theme(Brightness brightness) => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
);

/// A kit colour from the engine's ARGB int.
Color kitColor(int argb) => Color(argb);
