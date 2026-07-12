import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme.dart';
import '../../../models/user_model.dart';
import '../../../widgets/shopcell_logo.dart';

class SidebarItemData {
  const SidebarItemData({
    required this.icon,
    required this.label,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final bool enabled;
}

const sidebarItems = [
  SidebarItemData(icon: Icons.point_of_sale_rounded, label: 'Vente'),
  SidebarItemData(icon: Icons.inventory_2_rounded, label: "Gestion d'article"),
  SidebarItemData(icon: Icons.travel_explore_rounded, label: 'Recherche'),
  SidebarItemData(icon: Icons.settings_rounded, label: 'Paramètres'),
];

/// Sidebar premium avec le logo ShopCell en tête, l'utilisateur connecté,
/// puis le menu de navigation — dont "Gestion d'article" qui reprend
/// l'organisation de l'écran web `Produit/lst`.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.user,
    required this.onLogout,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final UserModel? user;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 264,
      color: AppColors.bgCard,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const ShopCellMark(size: 42),
                const SizedBox(width: 12),
                const ShopCellWordmark(fontSize: 20),
              ],
            ),
            const SizedBox(height: 26),
            const Divider(color: AppColors.border, height: 1),
            _UserTile(user: user),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: sidebarItems.length,
                itemBuilder: (context, i) {
                  final item = sidebarItems[i];
                  final selected = i == selectedIndex;
                  return _SidebarTile(
                    item: item,
                    selected: selected,
                    onTap: () {
                      if (!item.enabled) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${item.label} — bientôt disponible')),
                        );
                        return;
                      }
                      Scaffold.maybeOf(context)?.closeDrawer();
                      onSelect(i);
                    },
                  );
                },
              ),
            ),
            const Divider(color: AppColors.border, height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: _SidebarTile(
                item: const SidebarItemData(icon: Icons.logout_rounded, label: 'Déconnexion'),
                selected: false,
                danger: true,
                onTap: onLogout,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user});
  final UserModel? user;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accentGlow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person_rounded, color: AppColors.accentLight, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.nomComplet ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary),
                ),
                Text(
                  user?.roleLabel ?? '',
                  style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.item,
    required this.selected,
    required this.onTap,
    this.danger = false,
  });

  final SidebarItemData item;
  final bool selected;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? AppColors.red
        : selected
            ? AppColors.accentLight
            : item.enabled
                ? AppColors.textSecondary
                : AppColors.textMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected ? AppColors.accentGlow : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(item.icon, size: 19, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item.label,
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (!item.enabled && !danger)
                  const Icon(Icons.lock_clock_rounded, size: 14, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
