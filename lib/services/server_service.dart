import '../core/api_client.dart';

/// Gère la découverte et la mémorisation du serveur ShopCell (le PC/caisse
/// qui fait tourner le back-office CodeIgniter), sur le même principe que
/// l'écran web `QR/index` : celui-ci encode `<lien>/Mob/checkQR`, on scanne
/// ce lien, on en extrait la racine, puis on vérifie qu'il s'agit bien d'un
/// serveur ShopCell avant de le mémoriser en base locale.
class ServerService {
  ServerService._();
  static final ServerService instance = ServerService._();

  Future<String?> get savedServerUrl => ApiClient.instance.baseUrl;

  /// Extrait le lien racine à partir du contenu scanné.
  ///
  /// Le QR web encode `<racine>/Mob/checkQR` — une URL "jolie", SANS
  /// `/index.php/` (voir `MyQRCODE::getLienForApp()` + `QR::index()` côté
  /// serveur, qui construisent le lien à partir de `SCRIPT_NAME` sans jamais
  /// y insérer `index.php`). On strippe donc `/Mob/...` en priorité ; on
  /// garde le repli `/index.php` au cas où un déploiement différent
  /// produirait un jour l'ancienne forme.
  String extractRootLink(String scanned) {
    var link = scanned.trim();
    link = link.replaceAll(RegExp(r'/index\.php.*$'), '');
    link = link.replaceAll(RegExp(r'/Mob/.*$', caseSensitive: false), '');
    link = link.replaceAll(RegExp(r'/+$'), '');
    return link;
  }

  /// Lien(s) à essayer, dans l'ordre. Si l'utilisateur (ou le QR code) a
  /// précisé un protocole (`http://`/`https://`), on ne tente que celui-là —
  /// son choix est respecté tel quel. Sinon (IP ou nom d'hôte saisi nu, ex:
  /// `91.234.194.155/shopcell`), on essaie `https` en premier — le cas le
  /// plus courant pour un serveur exposé sur Internet — puis on se replie sur
  /// `http` (réseau local type WAMP, qui ne sert en général pas de TLS) :
  /// l'utilisateur n'a pas à se soucier du protocole exact.
  List<String> _candidates(String link) {
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(link)) {
      return [link];
    }
    return ['https://$link', 'http://$link'];
  }

  /// Valide le lien en interrogeant `Mob/checkQR` et, si la réponse est
  /// cohérente, le persiste dans la base locale (sqflite). Accepte aussi
  /// bien un lien complet (`https://91.234.194.155/shopcell/`) qu'une
  /// adresse nue (`91.234.194.155/shopcell`) — voir `_candidates()`.
  Future<ServerPairingResult> pairWithLink(String scannedContent) async {
    final root = extractRootLink(scannedContent);
    if (root.isEmpty) {
      return ServerPairingResult(success: false, message: 'Lien invalide.');
    }

    final candidates = _candidates(root);
    ServerPairingResult result = ServerPairingResult(success: false, message: 'Connexion au serveur impossible.');
    for (var i = 0; i < candidates.length; i++) {
      result = await _attempt(candidates[i]);
      if (result.success) return result;
      // Un échec réseau (mauvais protocole/port, hôte injoignable) justifie
      // d'essayer le candidat suivant ; une réponse du serveur qui n'est
      // simplement pas ShopCell est une vraie erreur, inutile d'insister.
      final isLast = i == candidates.length - 1;
      if (!result.isNetworkError || isLast) return result;
    }
    return result;
  }

  Future<ServerPairingResult> _attempt(String root) async {
    try {
      final data = await ApiClient.instance.get(
        'checkQR',
        overrideBaseUrl: root,
        timeout: const Duration(seconds: 8),
      );
      if (data is Map && data['info'] != null) {
        await ApiClient.instance.setBaseUrl(root);
        final nomBoutique = (data['info'] is Map) ? data['info']['appellation'] : null;
        return ServerPairingResult(success: true, boutique: nomBoutique?.toString());
      }
      return ServerPairingResult(success: false, message: "Ce lien ne correspond pas à un serveur ShopCell.");
    } on ApiException catch (e) {
      return ServerPairingResult(success: false, message: e.message, isNetworkError: true);
    } catch (_) {
      return ServerPairingResult(success: false, message: 'Connexion au serveur impossible.', isNetworkError: true);
    }
  }

  Future<void> forget() => ApiClient.instance.forgetBaseUrl();
}

class ServerPairingResult {
  ServerPairingResult({required this.success, this.message, this.boutique, this.isNetworkError = false});
  final bool success;
  final String? message;
  final String? boutique;
  /// Échec réseau (mauvais protocole/port, hôte injoignable) plutôt qu'une
  /// vraie réponse du serveur — justifie de retenter avec un autre protocole
  /// dans `ServerService.pairWithLink()`.
  final bool isNetworkError;
}
