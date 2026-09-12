import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'inline_field.dart';

class ClientInfoResult {
  ClientInfoResult({this.nom, this.prenom, this.telephone, this.cin});
  final String? nom;
  final String? prenom;
  final String? telephone;
  final String? cin;
}

/// Avant l'impression A4 d'un échange, propose de saisir/corriger les
/// informations client (nom, prénom, téléphone, CIN) à afficher sur la
/// facture — tous facultatifs, pré-remplis avec ce qu'on connaît déjà.
Future<ClientInfoResult?> showClientInfoDialog(
  BuildContext context, {
  String? initialNom,
  String? initialPrenom,
  String? initialTelephone,
  String? initialCin,
}) {
  final nomCtrl = TextEditingController(text: initialNom ?? '');
  final prenomCtrl = TextEditingController(text: initialPrenom ?? '');
  final telCtrl = TextEditingController(text: initialTelephone ?? '');
  final cinCtrl = TextEditingController(text: initialCin ?? '');

  return showDialog<ClientInfoResult>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.bgCard,
      title: const Text('Informations client', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Facultatif — à afficher sur la facture A4.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            InlineField(label: 'Nom', controller: nomCtrl, prefixIcon: Icons.person_rounded),
            const SizedBox(height: 10),
            InlineField(label: 'Prénom', controller: prenomCtrl, prefixIcon: Icons.badge_rounded),
            const SizedBox(height: 10),
            InlineField(label: 'Téléphone', controller: telCtrl, prefixIcon: Icons.phone_rounded, keyboardType: TextInputType.phone),
            const SizedBox(height: 10),
            InlineField(label: 'CIN', controller: cinCtrl, prefixIcon: Icons.badge_outlined),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(ClientInfoResult()),
          child: const Text('Ignorer'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(ClientInfoResult(
            nom: nomCtrl.text.trim().isEmpty ? null : nomCtrl.text.trim(),
            prenom: prenomCtrl.text.trim().isEmpty ? null : prenomCtrl.text.trim(),
            telephone: telCtrl.text.trim().isEmpty ? null : telCtrl.text.trim(),
            cin: cinCtrl.text.trim().isEmpty ? null : cinCtrl.text.trim(),
          )),
          child: const Text('Continuer', style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}
