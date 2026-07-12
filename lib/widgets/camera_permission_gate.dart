import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/theme.dart';
import 'gradient_button.dart';

enum _CameraPermState { checking, granted, denied, permanentlyDenied }

/// Encapsule la vérification/demande de permission caméra (utilisée par
/// l'écran de jumelage serveur et l'écran de vente par scan QR), pour éviter
/// de dupliquer cette logique dans chaque écran scanner.
class CameraPermissionGate extends StatefulWidget {
  const CameraPermissionGate({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  State<CameraPermissionGate> createState() => _CameraPermissionGateState();
}

class _CameraPermissionGateState extends State<CameraPermissionGate> with WidgetsBindingObserver {
  _CameraPermState _state = _CameraPermState.checking;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _state != _CameraPermState.granted) {
      _check();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _check() async {
    final status = await Permission.camera.status;
    if (!mounted) return;
    setState(() => _state = _map(status));
  }

  Future<void> _request() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    setState(() => _state = _map(status));
  }

  _CameraPermState _map(PermissionStatus status) {
    if (status.isGranted || status.isLimited) return _CameraPermState.granted;
    if (status.isPermanentlyDenied) return _CameraPermState.permanentlyDenied;
    return _CameraPermState.denied;
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _CameraPermState.checking:
        return const Center(child: CircularProgressIndicator(color: AppColors.accentLight));
      case _CameraPermState.granted:
        return widget.builder(context);
      case _CameraPermState.denied:
        return _PermissionRequest(
          message: "ShopCell a besoin d'accéder à la caméra pour scanner.",
          buttonLabel: 'Autoriser la caméra',
          onPressed: _request,
        );
      case _CameraPermState.permanentlyDenied:
        return _PermissionRequest(
          message: "L'accès à la caméra a été refusé définitivement.\nAutorisez-le dans les réglages de l'application.",
          buttonLabel: 'Ouvrir les réglages',
          onPressed: openAppSettings,
        );
    }
  }
}

class _PermissionRequest extends StatelessWidget {
  const _PermissionRequest({required this.message, required this.buttonLabel, required this.onPressed});

  final String message;
  final String buttonLabel;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.camera_alt_outlined, size: 40, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center, style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 24),
          GradientButton(label: buttonLabel, icon: Icons.lock_open_rounded, onPressed: onPressed),
        ],
      ),
    );
  }
}
