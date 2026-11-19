import '../core/api_client.dart';
import '../models/user_model.dart';

class ClientModel {
  ClientModel(this.data);
  final Map<String, dynamic> data;

  String? field(String k) {
    final v = data[k]?.toString().trim();
    return (v == null || v.isEmpty || v == 'null') ? null : v;
  }

  String get id => '${data['id_personnes']}';
  String get nom => field('nom_complet') ?? 'Sans nom';
  String? get prenom => field('prenom_personnes');
  String? get telephone => field('telephone');
  String? get email => field('email');
  String? get adresse => field('adresse');
  String? get cin => field('cin_personnes');
  String? get nif => field('nif_personnes');
  String? get stat => field('stat_personnes');
}

/// Menu "Clients" : liste (Mob/clients_list) et modification
/// (Mob/client_update, patron et magasinier, revalidé côté serveur).
class ClientService {
  ClientService._();
  static final ClientService instance = ClientService._();

  Future<List<ClientModel>> liste({String? arg}) async {
    final data = await ApiClient.instance.post('clients_list', fields: {if (arg != null && arg.trim().isNotEmpty) 'arg': arg.trim()});
    if (data is! List) return [];
    return data.whereType<Map>().map((e) => ClientModel(Map<String, dynamic>.from(e))).toList();
  }

  Future<(bool, String)> modifier({required UserModel user, required String idPersonnes, required Map<String, String> champs}) async {
    final data = await ApiClient.instance.post('client_update', fields: {
      'role': user.role,
      'id_personnes': idPersonnes,
      ...champs,
    });
    if (data is! Map) return (false, 'Réponse du serveur invalide.');
    return (data['error'] != true, '${data['msg'] ?? ''}');
  }
}
