import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../auth/login_screen.dart';
import '../credit/credit_clients_screen.dart';
import '../echange/echange_search_screen.dart';
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
const _parametresIndex = 5;

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

  Future<void> _loadUser() async {
    final user = await AuthService.instance.currentUser;
    if (mounted) setState(() => _user = user);
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
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= _wideBreakpoint;

    final sidebar = AppSidebar(
      selectedIndex: _selectedIndex,
      onSelect: _select,
      user: _user,
      onLogout: _logout,
    );

    final content = IndexedStack(index: _selectedIndex, children: _pages);

    if (wide) {
      return Scaffold(
        backgroundColor: AppColors.bgDeep,
        body: Row(
          children: [
            sidebar,
            const VerticalDivider(width: 1, color: AppColors.border),
            Expanded(child: content),
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
      ),
      body: content,
    );
  }
}
