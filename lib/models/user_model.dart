/// Reflète la ligne jointe user + personnes + type_personnes renvoyée par
/// `Mob/login` (voir application/models/User.php::select_func()).
class UserModel {
  UserModel({
    required this.idUser,
    required this.pseudo,
    required this.role,
    required this.nomComplet,
    required this.photo,
    required this.acces,
    required this.raw,
  });

  final String idUser;
  final String pseudo;
  final String role; // id_type_personnes: patron, magasinier, caissier, serveur, client...
  final String nomComplet;
  final String? photo;
  final int acces;

  /// Objet JSON brut, renvoyé tel quel au serveur pour les appels Mob/*
  /// qui exigent le champ `user` (le back-end ShopCell fait confiance au
  /// client mobile plutôt qu'à une session côté serveur pour ces routes).
  final Map<String, dynamic> raw;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      idUser: '${json['id_user'] ?? ''}',
      pseudo: '${json['pseudo'] ?? ''}',
      role: '${json['id_type_personnes'] ?? json['id_type_user'] ?? 'user'}',
      nomComplet: '${json['nom_complet'] ?? json['pseudo'] ?? ''}',
      photo: json['photo'] as String?,
      acces: int.tryParse('${json['acces'] ?? 1}') ?? 1,
      raw: json,
    );
  }

  Map<String, dynamic> toJson() => raw;

  /// Forme attendue par `VenteMob` côté serveur (`$user->id`), différente du
  /// JSON brut de session qui porte la clé `id_user`.
  Map<String, dynamic> get mobPayload => {'id': idUser, 'pseudo': pseudo};

  String get roleLabel {
    switch (role) {
      case 'patron':
        return 'Patron';
      case 'gerant':
        return 'Gérant';
      case 'magasinier':
        return 'Magasinier';
      case 'caissier':
        return 'Caissier';
      case 'serveur':
        return 'Serveur';
      case 'client':
        return 'Client';
      default:
        return 'Utilisateur';
    }
  }
}
