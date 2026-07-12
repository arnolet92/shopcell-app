import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'inline_field.dart';

/// Champ texte avec suggestions issues des valeurs existantes, sur le même
/// principe que les `<input list="...">` (datalist HTML) du formulaire web
/// Produit/addprod : l'utilisateur peut choisir une valeur existante ou
/// taper un texte inédit, qui sera "trouvé ou créé" côté serveur.
class AutocompleteLookupField extends StatelessWidget {
  const AutocompleteLookupField({
    super.key,
    required this.label,
    required this.controller,
    required this.suggestions,
    this.prefixIcon,
  });

  final String label;
  final TextEditingController controller;
  final List<String> suggestions;
  final IconData? prefixIcon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InlineField(label: label, controller: controller, prefixIcon: prefixIcon),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final query = value.text.trim().toLowerCase();
            final matches = suggestions
                .where((s) => s.toLowerCase() != query)
                .where((s) => query.isEmpty || s.toLowerCase().contains(query))
                .take(6)
                .toList();
            if (matches.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: matches
                    .map(
                      (s) => ActionChip(
                        label: Text(s, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                        backgroundColor: AppColors.bgElevated,
                        onPressed: () => controller.text = s,
                      ),
                    )
                    .toList(),
              ),
            );
          },
        ),
      ],
    );
  }
}
