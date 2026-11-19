import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/server_service.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/inline_field.dart';
import '../../widgets/phones_showcase.dart';
import '../../widgets/shopcell_logo.dart';
import '../home/home_shell.dart';
import '../pairing/qr_scan_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _pseudoCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 750))..forward();
  }

  @override
  void dispose() {
    _pseudoCtrl.dispose();
    _passwordCtrl.dispose();
    _anim.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_pseudoCtrl.text.trim().isEmpty || _passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Veuillez renseigner votre pseudo et votre mot de passe.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await AuthService.instance.login(pseudo: _pseudoCtrl.text.trim(), password: _passwordCtrl.text);

    if (!mounted) return;
    if (result.success) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
    } else {
      setState(() {
        _loading = false;
        _error = result.message ?? 'Connexion impossible.';
      });
    }
  }

  Future<void> _changeServer() async {
    await ServerService.instance.forget();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const QrScanScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.height < 720;
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Stack(
        children: [
          // fond : halos doux vert Android / argent, comme la page web
          const Positioned.fill(child: _LoginBackground()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: FadeTransition(
                    opacity: _anim,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(child: ShopCellLogo(height: compact ? 46 : 56)),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            'SMARTPHONES · ACCESSOIRES · RÉPARATION',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 2, color: const Color(0xFF3DDC84)),
                          ),
                        ),
                        SizedBox(height: compact ? 4 : 10),
                        PhonesShowcase(height: compact ? 190 : 250),
                        const SizedBox(height: 4),
                        const BrandChips(),
                        SizedBox(height: compact ? 16 : 22),
                        Container(
                          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFF161B24), Color(0xFF10141B)],
                            ),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 40, offset: const Offset(0, 20))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'OUVERTURE DE SESSION',
                                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2.4, color: const Color(0xFF3DDC84)),
                              ),
                              const SizedBox(height: 8),
                              // titre reduit automatiquement sur les petits ecrans (aucun debordement)
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      'Bienvenue chez ',
                                      style: GoogleFonts.outfit(fontSize: 25, fontWeight: FontWeight.w600, color: AppColors.textPrimary, letterSpacing: -0.4),
                                    ),
                                    ShaderMask(
                                      shaderCallback: (r) =>
                                          const LinearGradient(colors: [Color(0xFFC8F7DA), Color(0xFF3DDC84), Color(0xFF16A34A)]).createShader(r),
                                      child: Text(
                                        'ShopCell',
                                        style: GoogleFonts.outfit(fontSize: 25, fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: -0.4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Connectez-vous pour ouvrir la caisse.',
                                style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                              ),
                              const SizedBox(height: 16),
                              InlineField(
                                label: 'Pseudo',
                                controller: _pseudoCtrl,
                                prefixIcon: Icons.person_outline_rounded,
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 18),
                              InlineField(
                                label: 'Mot de passe',
                                controller: _passwordCtrl,
                                obscureText: _obscure,
                                prefixIcon: Icons.lock_outline_rounded,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _submit(),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 19, color: AppColors.textMuted),
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                ),
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: AppColors.red.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppColors.red.withValues(alpha: 0.35)),
                                  ),
                                  child: Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
                                ),
                              ],
                              const SizedBox(height: 24),
                              GradientButton(label: 'Se connecter', icon: Icons.arrow_forward_rounded, loading: _loading, onPressed: _submit),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _loading ? null : _changeServer,
                          icon: const Icon(Icons.qr_code_scanner_rounded, size: 18, color: AppColors.accentLight),
                          label: const Text('Scanner le lien du serveur', style: TextStyle(color: AppColors.accentLight)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fond de l'écran de connexion : halos doux vert Android et argent.
class _LoginBackground extends StatelessWidget {
  const _LoginBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -120,
          left: -80,
          child: Container(
            width: 420,
            height: 420,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [Color(0x2E3DDC84), Color(0x003DDC84)]),
            ),
          ),
        ),
        Positioned(
          bottom: -140,
          right: -100,
          child: Container(
            width: 420,
            height: 420,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [Color(0x1F94A3B8), Color(0x0094A3B8)]),
            ),
          ),
        ),
      ],
    );
  }
}
