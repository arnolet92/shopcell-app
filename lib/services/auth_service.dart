import '../core/api_client.dart';
import '../core/local_db.dart';
import '../models/user_model.dart';

/// Authentification via `Mob/login` (application/modules/Mob/models/ApiManage.php::login()).
///
/// Ce back-end ne renvoie pas de jeton/session HTTP pour les routes `Mob/*` :
/// on persiste donc simplement l'objet `user` renvoyé par le serveur dans la
/// base locale (sqflite) et on le renvoie tel quel dans le corps des appels
/// qui en ont besoin, comme le fait déjà l'app mobile "officielle" décrite
/// dans le contrôleur (`$this->input->post("user")` un peu partout dans Mob.php).
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  UserModel? _current;

  Future<UserModel?> get currentUser async {
    if (_current != null) return _current;
    final raw = await LocalDb.instance.loadSession();
    if (raw == null) return null;
    _current = UserModel.fromJson(raw);
    return _current;
  }

  Future<LoginResult> login({required String pseudo, required String password}) async {
    try {
      final data = await ApiClient.instance.post('login', fields: {
        'pseudo': pseudo,
        'password': password,
      });

      if (data is! Map) {
        return LoginResult(success: false, message: 'Réponse du serveur invalide.');
      }

      final error = data['error'] == true;
      final message = data['msg']?.toString();
      final userJson = data['user'];

      if (error || userJson is! Map) {
        return LoginResult(success: false, message: message ?? 'Identifiants incorrects.');
      }

      final userMap = Map<String, dynamic>.from(userJson);
      final user = UserModel.fromJson(userMap);
      await LocalDb.instance.saveSession(userMap);
      _current = user;
      return LoginResult(success: true, message: message, user: user);
    } on ApiException catch (e) {
      return LoginResult(success: false, message: e.message);
    } catch (_) {
      return LoginResult(success: false, message: 'Une erreur inattendue est survenue.');
    }
  }

  Future<void> logout() async {
    try {
      await ApiClient.instance.post('logout');
    } catch (_) {
      // La déconnexion locale doit réussir même si le serveur est injoignable.
    }
    _current = null;
    await LocalDb.instance.clearSession();
  }
}

class LoginResult {
  LoginResult({required this.success, this.message, this.user});
  final bool success;
  final String? message;
  final UserModel? user;
}
