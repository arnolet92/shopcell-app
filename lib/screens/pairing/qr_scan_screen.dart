import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

import '../../core/theme.dart';
import '../../services/server_service.dart';
import '../../widgets/camera_permission_gate.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/inline_field.dart';
import '../../widgets/shopcell_logo.dart';
import '../auth/login_screen.dart';

/// Écran de jumelage : scanne le QR code affiché par le back-office web
/// (bouton "Connexion au serveur" -> `QR/index`, qui encode
/// `<lien>/Mob/checkQR`) pour découvrir automatiquement l'adresse du serveur
/// ShopCell sur le réseau local, la valider, puis la mémoriser en base
/// locale avant de passer à l'écran de connexion.
///
/// Note technique : `mobile_scanner` (CameraX/ML-Kit) a échoué de façon
/// identique en v6 et v7 sur les appareils de test (NPE générique
/// `getClass() on a null object reference`), avant même d'atteindre le code
/// applicatif. On utilise ici `qr_code_scanner_plus`, qui repose sur un
/// pipeline caméra entièrement différent (zxing natif, pas de CameraX), pour
/// écarter un souci propre à CameraX sur ce type d'appareil.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _qrKey = GlobalKey(debugLabel: 'qr_pairing');
  QRViewController? _qrController;
  final _manualLinkController = TextEditingController();

  bool _busy = false;
  String? _error;
  bool _manualMode = false;

  @override
  void dispose() {
    _manualLinkController.dispose();
    super.dispose();
  }

  void _onQrViewCreated(QRViewController controller) {
    _qrController = controller;
    controller.scannedDataStream.listen((scanData) {
      final code = scanData.code;
      if (code != null) _handleScan(code);
    });
  }

  Future<void> _handleScan(String raw) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await ServerService.instance.pairWithLink(raw);

    if (!mounted) return;
    if (result.success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    setState(() {
      _busy = false;
      _error = result.message ?? 'Connexion impossible.';
    });
    await _qrController?.resumeCamera();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            const ShopCellMark(size: 48),
            const SizedBox(height: 14),
            Text(
              'Connexion au serveur',
              style: GoogleFonts.inter(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _manualMode
                    ? "Saisissez le lien affiché sur l'écran de la caisse."
                    : "Scannez le QR code affiché sur l'écran d'accueil du poste de caisse (bouton QR code).",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _manualMode
                  ? _buildManualForm()
                  : CameraPermissionGate(builder: (_) => _buildScanner()),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.red, fontSize: 13),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _manualMode = !_manualMode;
                          _error = null;
                        }),
                child: Text(
                  _manualMode ? 'Revenir au scan du QR code' : "Saisir le lien manuellement",
                  style: const TextStyle(color: AppColors.accentLight, fontSize: 13.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            fit: StackFit.expand,
            children: [
              QRView(
                key: _qrKey,
                onQRViewCreated: _onQrViewCreated,
                overlay: QrScannerOverlayShape(
                  borderColor: AppColors.accent,
                  borderRadius: 28,
                  borderLength: 30,
                  borderWidth: 8,
                  cutOutSize: 220,
                ),
                onPermissionSet: (controller, granted) {
                  if (!granted && mounted) {
                    setState(() => _error = "Accès à la caméra refusé par le système.");
                  }
                },
              ),
              if (_busy)
                Container(
                  color: Colors.black.withValues(alpha: 0.55),
                  child: const Center(
                    child: CircularProgressIndicator(color: AppColors.accentLight),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManualForm() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InlineField(
            label: 'Lien du serveur (ex: http://192.168.1.10/shopcell)',
            controller: _manualLinkController,
            prefixIcon: Icons.link_rounded,
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 28),
          GradientButton(
            label: 'Se connecter au serveur',
            icon: Icons.wifi_tethering_rounded,
            loading: _busy,
            onPressed: () => _handleScan(_manualLinkController.text),
          ),
        ],
      ),
    );
  }
}
