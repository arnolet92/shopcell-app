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

const _vert = Color(0xFF3DDC84);
const _gradTitre = LinearGradient(colors: [Color(0xFFC8F7DA), Color(0xFF3DDC84), Color(0xFF16A34A)]);
// Couleurs des avatars sans photo (mêmes que la page web).
const _avatarColors = [
  [Color(0xFF6EE7B7), Color(0xFF047857)],
  [Color(0xFF93C5FD), Color(0xFF1D4ED8)],
  [Color(0xFFC4B5FD), Color(0xFF6D28D9)],
  [Color(0xFFFCD34D), Color(0xFFB45309)],
  [Color(0xFFFDA4AF), Color(0xFFBE123C)],
  [Color(0xFF5EEAD4), Color(0xFF0F766E)],
  [Color(0xFFCBD5E1), Color(0xFF475569)],
];

/// Connexion : comme la page web, liste des comptes (avatar + pseudo, sans le
/// rôle) ; un tap ouvre un panneau qui glisse depuis la droite et demande le
/// mot de passe. Formulaire pseudo / mot de passe classique en repli.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.profilsApercu});

  /// Aperçu / tests uniquement : liste de comptes fournie directement au lieu
  /// de l'appel serveur `Mob/users_login`.
  @visibleForTesting
  final List<LoginProfile>? profilsApercu;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _pseudoCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;
  List<LoginProfile>? _profils; // null = chargement
  bool _manuel = false;

  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 750))..forward();
    _chargerProfils();
  }

  @override
  void dispose() {
    _pseudoCtrl.dispose();
    _passwordCtrl.dispose();
    _anim.dispose();
    super.dispose();
  }

  Future<void> _chargerProfils() async {
    final list = widget.profilsApercu ?? await AuthService.instance.profils();
    if (!mounted) return;
    setState(() => _profils = list);
  }

  void _ouvrirAccueil() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
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
      _ouvrirAccueil();
    } else {
      setState(() {
        _loading = false;
        _error = result.message ?? 'Connexion impossible.';
      });
    }
  }

  /// Panneau "mot de passe" qui glisse depuis la droite (comme sur le web).
  Future<void> _ouvrirPanneau(LoginProfile p) async {
    final ok = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fermer',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (context, a1, a2) => Align(
        alignment: Alignment.centerRight,
        child: _PasswordPanel(profil: p),
      ),
      transitionBuilder: (context, anim, a2, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(curved),
          child: child,
        );
      },
    );
    if (ok == true && mounted) _ouvrirAccueil();
  }

  Future<void> _changeServer() async {
    await ServerService.instance.forget();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const QrScanScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.height < 720;
    final profils = _profils;
    final avecProfils = profils != null && profils.isNotEmpty;
    final formulaireVisible = (profils != null && profils.isEmpty) || _manuel;
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Stack(
        children: [
          const Positioned.fill(child: _LoginBackground()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: FadeTransition(
                    opacity: _anim,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(child: ShopCellLogo(height: compact ? 44 : 54)),
                        const SizedBox(height: 8),
                        Text(
                          'SMARTPHONES · ACCESSOIRES · RÉPARATION',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 2, color: _vert),
                        ),
                        SizedBox(height: compact ? 2 : 8),
                        PhonesShowcase(height: compact ? 170 : 220),
                        const SizedBox(height: 2),
                        const BrandChips(),
                        SizedBox(height: compact ? 14 : 20),
                        Container(
                          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
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
                                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2.4, color: _vert),
                              ),
                              const SizedBox(height: 8),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    const TextSpan(text: 'Qui est en '),
                                    TextSpan(
                                      text: 'boutique',
                                      style: TextStyle(foreground: Paint()..shader = _gradTitre.createShader(const Rect.fromLTWH(0, 0, 120, 30))),
                                    ),
                                    const TextSpan(text: ' aujourd’hui ?'),
                                  ],
                                ),
                                style: GoogleFonts.outfit(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                  letterSpacing: -0.4,
                                  height: 1.15,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                avecProfils ? 'Touchez votre profil puis saisissez votre mot de passe.' : 'Connectez-vous pour ouvrir la caisse.',
                                style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                              ),
                              const SizedBox(height: 16),
                              if (profils == null)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 22),
                                  child: Center(
                                    child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4, color: _vert)),
                                  ),
                                ),
                              if (avecProfils) ...[
                                LayoutBuilder(
                                  builder: (context, c) {
                                    final cols = c.maxWidth >= 400 ? 4 : 3;
                                    const gap = 10.0;
                                    final w = (c.maxWidth - gap * (cols - 1)) / cols;
                                    return Wrap(
                                      spacing: gap,
                                      runSpacing: gap,
                                      children: [
                                        for (final p in profils)
                                          SizedBox(
                                            width: w,
                                            child: _ProfileCard(profil: p, onTap: () => _ouvrirPanneau(p)),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () => setState(() => _manuel = !_manuel),
                                    icon: const Icon(Icons.lock_outline_rounded, size: 16, color: _vert),
                                    label: Text(
                                      'Se connecter avec identifiant et mot de passe',
                                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: _vert),
                                    ),
                                  ),
                                ),
                              ],
                              AnimatedSize(
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.topCenter,
                                child: formulaireVisible ? _formulaire() : const SizedBox(width: double.infinity),
                              ),
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

  Widget _formulaire() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        InlineField(label: 'Pseudo', controller: _pseudoCtrl, prefixIcon: Icons.person_outline_rounded, textInputAction: TextInputAction.next),
        const SizedBox(height: 16),
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
        if (_error != null) ...[const SizedBox(height: 14), _ErrorBox(message: _error!)],
        const SizedBox(height: 22),
        GradientButton(label: 'Se connecter', icon: Icons.arrow_forward_rounded, loading: _loading, onPressed: _submit),
      ],
    );
  }
}

/// Avatar rond : photo du compte si elle charge, sinon initiales sur dégradé.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.profil, this.size = 58});
  final LoginProfile profil;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = _avatarColors[(int.tryParse(profil.idUser) ?? profil.pseudo.length) % _avatarColors.length];
    final initiales = Center(
      child: Text(
        profil.initiales,
        style: GoogleFonts.outfit(fontSize: size * 0.34, fontWeight: FontWeight.w600, color: Colors.white),
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c),
        border: Border.all(color: const Color(0xFF10141B), width: 3),
        boxShadow: [
          BoxShadow(color: _vert.withValues(alpha: 0.28), spreadRadius: 1.2),
          BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 18, offset: const Offset(0, 10)),
        ],
      ),
      child: ClipOval(
        child: profil.photo == null
            ? initiales
            : Image.network(profil.photo!, fit: BoxFit.cover, width: size, height: size, errorBuilder: (_, _, _) => initiales),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profil, required this.onTap});
  final LoginProfile profil;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(6, 16, 6, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1A202B), Color(0xFF12161E)]),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Avatar(profil: profil),
              const SizedBox(height: 10),
              Text(
                profil.pseudo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Panneau latéral droit : "Bonjour, `pseudo`" + mot de passe.
class _PasswordPanel extends StatefulWidget {
  const _PasswordPanel({required this.profil});
  final LoginProfile profil;

  @override
  State<_PasswordPanel> createState() => _PasswordPanelState();
}

class _PasswordPanelState extends State<_PasswordPanel> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_ctrl.text.isEmpty) {
      setState(() => _error = 'Saisissez votre mot de passe.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await AuthService.instance.login(pseudo: widget.profil.pseudo, password: _ctrl.text);
    if (!mounted) return;
    if (r.success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _loading = false;
        _error = (r.message == null || r.message!.toLowerCase().contains('identifiant')) ? 'Mot de passe incorrect. Réessayez.' : r.message;
        _ctrl.clear();
      });
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final width = mq.size.width < 460 ? mq.size.width : 420.0;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        height: double.infinity,
        // fond opaque (un gradient annule la couleur d'une BoxDecoration : le
        // halo vert est donc dans un degrade dont la base reste #0A0D12 opaque)
        decoration: BoxDecoration(
          gradient: const RadialGradient(center: Alignment(0, -1.1), radius: 1.2, colors: [Color(0xFF12241B), Color(0xFF0A0D12)]),
          border: Border(left: BorderSide(color: _vert.withValues(alpha: 0.26))),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 60, offset: const Offset(-20, 0))],
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 10,
                right: 12,
                child: IconButton(
                  onPressed: _loading ? null : () => Navigator.of(context).pop(false),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF161B24),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(26, 60, 26, 24 + mq.viewInsets.bottom),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(child: _Avatar(profil: widget.profil, size: 100)),
                        const SizedBox(height: 20),
                        Text(
                          'Bonjour, ${widget.profil.pseudo}',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.w600, color: AppColors.textPrimary, letterSpacing: -0.3),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Saisissez votre mot de passe pour ouvrir la session',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 24),
                        if (_error != null) ...[_ErrorBox(message: _error!), const SizedBox(height: 14)],
                        TextField(
                          controller: _ctrl,
                          focusNode: _focus,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _valider(),
                          style: GoogleFonts.inter(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          cursorColor: _vert,
                          decoration: InputDecoration(
                            hintText: 'Mot de passe',
                            filled: true,
                            fillColor: const Color(0xFF07090D),
                            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 19, color: AppColors.textMuted),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 19, color: AppColors.textMuted),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                            contentPadding: const EdgeInsets.symmetric(vertical: 16),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: _vert, width: 1.4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        GradientButton(label: 'Ouvrir la session', icon: Icons.arrow_forward_rounded, loading: _loading, onPressed: _valider),
                        const SizedBox(height: 14),
                        TextButton(
                          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
                          child: Text(
                            'Ce n’est pas vous ? Changer de profil',
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.35)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.red, fontSize: 13, fontWeight: FontWeight.w600),
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
