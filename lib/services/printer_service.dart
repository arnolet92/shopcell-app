import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';

import '../core/local_db.dart';
import '../models/printer_config.dart';

class PrintResult {
  PrintResult({required this.success, this.message});
  final bool success;
  final String? message;
}

/// Envoie des tickets ESC/POS (générés avec `esc_pos_utils_plus`, voir
/// `TicketBuilder`) vers l'imprimante configurée par l'utilisateur, en WiFi
/// (socket réseau brut, port 9100 par défaut) ou en Bluetooth (profil SPP
/// classique via `print_bluetooth_thermal`).
class PrinterService {
  PrinterService._();
  static final PrinterService instance = PrinterService._();

  PrinterConfig? _config;

  Future<PrinterConfig?> get config async {
    if (_config != null) return _config;
    final raw = await LocalDb.instance.getConfig(LocalDb.keyPrinterConfig);
    _config = PrinterConfig.decode(raw);
    return _config;
  }

  Future<void> saveConfig(PrinterConfig config) async {
    _config = config;
    await LocalDb.instance.setConfig(LocalDb.keyPrinterConfig, PrinterConfig.encode(config));
  }

  Future<void> clearConfig() async {
    _config = null;
    await LocalDb.instance.clearConfig(LocalDb.keyPrinterConfig);
  }

  Future<List<BluetoothInfo>> pairedBluetoothPrinters() async {
    return PrintBluetoothThermal.pairedBluetooths;
  }

  // ---- Imprimante A4 (système Android, ex: Canon G3800) ----

  bool? _a4Enabled;

  Future<bool> get isA4Enabled async {
    if (_a4Enabled != null) return _a4Enabled!;
    final raw = await LocalDb.instance.getConfig(LocalDb.keyA4PrinterEnabled);
    _a4Enabled = raw == '1';
    return _a4Enabled!;
  }

  Future<void> setA4Enabled(bool enabled) async {
    _a4Enabled = enabled;
    await LocalDb.instance.setConfig(LocalDb.keyA4PrinterEnabled, enabled ? '1' : '0');
  }

  /// Ouvre le système d'impression Android (sélection d'imprimante réseau/
  /// Mopria, ex: Canon G3800) avec le PDF donné.
  Future<PrintResult> printPdf(pw.Document doc, {String docName = 'Ticket'}) async {
    try {
      final bytes = await doc.save();
      final ok = await Printing.layoutPdf(
        onLayout: (_) async => Uint8List.fromList(bytes),
        name: docName,
      );
      return PrintResult(success: ok, message: ok ? null : 'Impression annulée.');
    } catch (e) {
      return PrintResult(success: false, message: "Impression A4 impossible : $e");
    }
  }

  /// Repli quand le sélecteur d'imprimantes intégré ne trouve pas
  /// l'imprimante (bug connu de découverte réseau selon les appareils) :
  /// ouvre le menu de partage Android standard, pour imprimer via une autre
  /// application (Google Drive, un lecteur PDF...) où l'imprimante est déjà
  /// détectée.
  Future<PrintResult> sharePdf(pw.Document doc, {String filename = 'ticket.pdf'}) async {
    try {
      final bytes = await doc.save();
      final ok = await Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: filename);
      return PrintResult(success: ok);
    } catch (e) {
      return PrintResult(success: false, message: "Partage du PDF impossible : $e");
    }
  }

  Future<PrintResult> printBytes(List<int> bytes) async {
    final cfg = await config;
    if (cfg == null || !cfg.isConfigured) {
      return PrintResult(success: false, message: "Aucune imprimante configurée. Ouvrez Paramètres > Imprimante.");
    }
    if (cfg.type == PrinterType.wifi) {
      return _printWifi(cfg, bytes);
    }
    return _printBluetooth(cfg, bytes);
  }

  Future<PrintResult> _printWifi(PrinterConfig cfg, List<int> bytes) async {
    Socket? socket;
    try {
      socket = await Socket.connect(cfg.wifiIp, cfg.wifiPort, timeout: const Duration(seconds: 6));
      socket.add(bytes);
      await socket.flush();
      return PrintResult(success: true);
    } catch (e) {
      return PrintResult(success: false, message: "Connexion à l'imprimante ${cfg.wifiIp}:${cfg.wifiPort} impossible : $e");
    } finally {
      socket?.destroy();
    }
  }

  Future<PrintResult> _printBluetooth(PrinterConfig cfg, List<int> bytes) async {
    try {
      final alreadyConnected = await PrintBluetoothThermal.connectionStatus;
      if (!alreadyConnected) {
        final connected = await PrintBluetoothThermal.connect(macPrinterAddress: cfg.bluetoothMac!);
        if (!connected) {
          return PrintResult(success: false, message: "Connexion Bluetooth à ${cfg.label} impossible.");
        }
      }
      final ok = await PrintBluetoothThermal.writeBytes(bytes);
      return PrintResult(success: ok, message: ok ? null : "Échec de l'impression Bluetooth.");
    } catch (e) {
      return PrintResult(success: false, message: 'Erreur Bluetooth : $e');
    }
  }
}
