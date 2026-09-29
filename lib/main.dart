import 'dart:io';

import 'package:flutter/material.dart';

import 'core/http_overrides.dart';
import 'core/theme.dart';
import 'screens/splash/splash_screen.dart';

void main() {
  HttpOverrides.global = ShopCellHttpOverrides();
  runApp(const ShopCellApp());
}

class ShopCellApp extends StatelessWidget {
  const ShopCellApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShopCell',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const SplashScreen(),
    );
  }
}
