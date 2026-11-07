import 'dart:convert';

import '../core/api_client.dart';
import '../models/produit_model.dart';
import '../models/user_model.dart';

double _d(dynamic v) => double.tryParse('${v ?? ''}') ?? 0;

class SortieResume {
  SortieResume({
    required this.id,
    required this.numero,
    required this.note,
    required this.date,
    required this.nomUser,
    required this.nbLignes,
    required this.statut,
  });

  factory SortieResume.fromJson(Map<String, dynamic> j) => SortieResume(
        id: '${j['id_sortie'] ?? ''}',
        numero: '${j['numero_sortie'] ?? ''}',
        note: '${j['note_sortie'] ?? ''}',
        date: '${j['sortie_at'] ?? ''}',
        nomUser: '${j['nom_user'] ?? ''}',
        nbLignes: _d(j['nb_lignes']).toInt(),
        statut: '${j['statut'] ?? ''}',
      );

  final String id;
  final String numero;
  final String note;
  final String date;
  final String nomUser;
  final int nbLignes;
  final String statut;
}

class SortieLigne {
  SortieLigne({
    required this.id,
    required this.designation,
    required this.qte,
    required this.annule,
    this.numSerie,
    this.imei1,
  });

  factory SortieLigne.fromJson(Map<String, dynamic> j) => SortieLigne(
        id: '${j['id_sortie_ligne'] ?? ''}',
        designation: '${j['designation_ligne'] ?? ''}',
        qte: _d(j['qte_sortie']),
        annule: '${j['is_annule']}' == '1',
        numSerie: j['num_serie_ligne']?.toString(),
        imei1: j['imei1_ligne']?.toString(),
      );

  final String id;
  final String designation;
  final double qte;
  final bool annule;
  final String? numSerie;
  final String? imei1;
}

class SortieDetail {
  SortieDetail({required this.resume, required this.lignes});
  final SortieResume resume;
  final List<SortieLigne> lignes;
}

class SortieAction {
  SortieAction({required this.success, this.message, this.idSortie});
  final bool success;
  final String? message;
  final String? idSortie;
}

/// Sorties de stock hors vente : miroir mobile du module web `Sortie`.
class SortieService {
  SortieService._();
  static final SortieService instance = SortieService._();

  SortieAction _action(dynamic data) {
    if (data is! Map) return SortieAction(success: false, message: 'Réponse du serveur invalide.');
    return SortieAction(success: data['error'] != true, message: data['msg']?.toString(), idSortie: data['id_sortie']?.toString());
  }

  Future<List<SortieResume>> liste({String? arg}) async {
    final data = await ApiClient.instance.post('sorties_list', fields: {if (arg != null && arg.trim().isNotEmpty) 'arg': arg.trim()});
    if (data is! List) return [];
    return data.whereType<Map>().map((e) => SortieResume.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<SortieDetail?> detail(String idSortie) async {
    final data = await ApiClient.instance.post('sortie_detail', fields: {'id_sortie': idSortie});
    if (data is! Map) return null;
    final lignes = data['lignes'];
    return SortieDetail(
      resume: SortieResume.fromJson(Map<String, dynamic>.from(data)),
      lignes: lignes is List ? lignes.whereType<Map>().map((e) => SortieLigne.fromJson(Map<String, dynamic>.from(e))).toList() : [],
    );
  }

  Future<List<ProduitModel>> rechercher(String arg) async {
    if (arg.trim().isEmpty) return [];
    final data = await ApiClient.instance.post('sortie_search', fields: {'arg': arg});
    if (data is! List) return [];
    return data.whereType<Map>().map((e) => ProduitModel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<SortieAction> valider({required Map<String, int> quantites, required String note, required UserModel user}) async {
    final items = quantites.entries.map((e) => {'id_produits': e.key, 'qte': e.value}).toList();
    return _action(await ApiClient.instance.post('sortie_valider', fields: {
      'items': jsonEncode(items),
      'note': note,
      'user': jsonEncode(user.mobPayload),
    }));
  }

  /// [idLigne] nul : annule toute la sortie.
  Future<SortieAction> annuler({required String idSortie, String? idLigne, required UserModel user}) async {
    return _action(await ApiClient.instance.post('sortie_annuler', fields: {
      'id_sortie': idSortie,
      'id_ligne': ?idLigne,
      'user': jsonEncode(user.mobPayload),
    }));
  }
}
