import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/facture_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/facture_service.dart';
import '../auth/login_screen.dart';
import '../credit/credit_clients_screen.dart';
import '../echange/echange_search_screen.dart';
import '../facture/facture_list_screen.dart';
import '../produit/produit_list_screen.dart';
import '../search/smart_search_screen.dart';
import '../settings/printer_settings_screen.dart';
import '../vente/vente_home_screen.dart';
import 'widgets/app_sidebar.dart';

const _wideBreakpoint = 760.0;
// Positions dans sidebarItems : ces entrées ouvrent un écran dédié (push)
// plutôt qu'un onglet persistant de l'IndexedStack.
const _rechercheIndex = 2;
const _echangeIndex = 3;
const _creditIndex = 4;
const _facturesPayeesIndex = 5;
const _facturesAnnuleesIndex = 6;
const _parametresIndex = 7;
// "Annulation en attente" (patron uniquement) est toujours ajoutée en
// DERNIÈRE position par sidebarItemsFor() — voir app_sidebar.dart — donc son
// index est simplement la longueur de la liste de base, jamais un index fixe
// qui décalerait les autres comptes.
final _annulationAttenteIndex = sidebarItems.length;

/// Coquille principale post-connexion : sidebar ShopCell + zone de contenu.
/// Page par défaut = Vente (demandé explicitement), la deuxième entrée
/// pleinement fonctionnelle est "Gestion d'article" (miroir de `Produit/lst`).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;
  UserModel? _user;
  int _pendingAnnulationCount = 0;
  Timer? _pollTimer;

  static const _pageTitles = ['Vente', "Gestion d'article"];
  static final _pages = [
    const VenteHomeScreen(),
    const ProduitListScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final user = await AuthService.instance.currentUser;
    if (!mounted) return;
    setState(() => _user = user);
    // Icône notification "Annulation en attente" : patron uniquement,
    // rafraîchie périodiquement tant que l'app reste ouverte (pas de push
    // serveur->mobile disponible ici, un simple polling suffit pour ce
    // volume de données).
    if (user?.role == 'patron') {
      _pollAnnulationAttente();
      _pollTimer = Timer.periodic(const Duration(seconds: 45), (_) => _pollAnnulationAttente());
    }
  }

  Future<void> _pollAnnulationAttente() async {
    final count = await FactureService.instance.countAnnulationAttente(role: 'patron');
    if (mounted) setState(() => _pendingAnnulationCount = count);
  }

  void _openAnnulationAttente() {
    if (_user == null) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => FactureListScreen(mode: FactureListMode.attente, user: _user!)))
        .then((_) => _pollAnnulationAttente());
  }

  Future<void> _logout() async {
    await AuthService.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _select(int index) {
    if (index == _rechercheIndex) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SmartSearchScreen()));
      return;
    }
    if (index == _parametresIndex) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()));
      return;
    }
    if (index == _echangeIndex) {
      if (_user != null) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => EchangeSearchScreen(user: _user!)));
      }
      return;
    }
    if (index == _creditIndex) {
      if (_user != null) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => CreditClientsScreen(user: _user!)));
      }
      return;
    }
    if (index == _facturesPayeesIndex) {
      if (_user != null) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => FactureListScreen(mode: FactureListMode.payee, user: _user!)));
      }
      return;
    }
    if (index == _facturesAnnuleesIndex) {
      if (_user != null) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => FactureListScreen(mode: FactureListMode.annulee, user: _user!)));
      }
      return;
    }
    if (index == _annulationAttenteIndex) {
      _openAnnulationAttente();
      return;
    }
    setState(() => _selectedIndex = index);
  }

  /// Icône notification "Annulation en attente" — patron uniquement, ne
  /// s'affiche que s'il y a au moins une demande, clignote pour attirer
  /// l'attention (voir BlinkingDot).
  Widget? _bellIcon() {
    if (_user?.role != 'patron' || _pendingAnnulationCount == 0) return null;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: _openAnnulationAttente,
          icon: const Icon(Icons.notifications_rounded, color: AppColors.orange),
          tooltip: 'Annulation en attente',
        ),
        Positioned(
          right: 6,
          top: 6,
          child: IgnorePointer(
            child: BlinkingDot(
              child: Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(color: AppColors.orange, shape: BoxShape.circle),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= _wideBreakpoint;

    final sidebar = AppSidebar(
      selectedIndex: _selectedIndex,
      onSelect: _select,
      user: _user,
      onLogout: _logout,
      pendingAnnulationCount: _pendingAnnulationCount,
    );

    final content = IndexedStack(index: _selectedIndex, children: _pages);
    final bell = _bellIcon();

    if (wide) {
      return Scaffold(
        backgroundColor: AppColors.bgDeep,
        body: Row(
          children: [
            sidebar,
            const VerticalDivider(width: 1, color: AppColors.border),
            Expanded(
              child: Stack(
                children: [
                  content,
                  if (bell != null) Positioned(top: 8, right: 12, child: bell),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      drawer: Drawer(backgroundColor: AppColors.bgCard, width: 264, child: sidebar),
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        title: Text(
          _pageTitles[_selectedIndex],
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.textPrimary),
        ),
        actions: [?bell],
      ),
      body: content,
    );
  }
}
