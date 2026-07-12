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
  /// Le QR web encode typiquement `http://192.168.x.x/shopcell/index.php/Mob/checkQR`.
  String extractRootLink(String scanned) {
    var link = scanned.trim();
    link = link.replaceAll(RegExp(r'/index\.php.*$'), '');
    link = link.replaceAll(RegExp(r'/+$'), '');
    return link;
  }

  /// Valide le lien en interrogeant `Mob/checkQR` et, si la réponse est
  /// cohérente, le persiste dans la base locale (sqflite).
  Future<ServerPairingResult> pairWithLink(String scannedContent) async {
    final root = extractRootLink(scannedContent);
    if (root.isEmpty || !root.startsWith('http')) {
      return ServerPairingResult(success: false, message: 'QR code invalide.');
    }
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
      return ServerPairingResult(success: false, message: e.message);
    } catch (_) {
      return ServerPairingResult(success: false, message: 'Connexion au serveur impossible.');
    }
  }

  Future<void> forget() => ApiClient.instance.forgetBaseUrl();
}

class ServerPairingResult {
  ServerPairingResult({required this.success, this.message, this.boutique});
  final bool success;
  final String? message;
  final String? boutique;
}
