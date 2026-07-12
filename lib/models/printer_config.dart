import 'dart:convert';

enum PrinterType { wifi, bluetooth }

/// Configuration de l'imprimante ticket (WiFi ou Bluetooth), persistée en
/// base locale (voir `LocalDb.keyPrinterConfig`).
class PrinterConfig {
  PrinterConfig({
    required this.type,
    this.wifiIp,
    this.wifiPort = 9100,
    this.bluetoothMac,
    this.bluetoothName,
  });

  final PrinterType type;
  final String? wifiIp;
  final int wifiPort;
  final String? bluetoothMac;
  final String? bluetoothName;

  bool get isConfigured => type == PrinterType.wifi ? (wifiIp?.isNotEmpty ?? false) : (bluetoothMac?.isNotEmpty ?? false);

  String get label {
    if (type == PrinterType.wifi) {
      return wifiIp != null ? '$wifiIp:$wifiPort' : 'WiFi (non configurée)';
    }
    return bluetoothName ?? bluetoothMac ?? 'Bluetooth (non configurée)';
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'wifiIp': wifiIp,
        'wifiPort': wifiPort,
        'bluetoothMac': bluetoothMac,
        'bluetoothName': bluetoothName,
      };

  factory PrinterConfig.fromJson(Map<String, dynamic> json) => PrinterConfig(
        type: json['type'] == 'bluetooth' ? PrinterType.bluetooth : PrinterType.wifi,
        wifiIp: json['wifiIp'] as String?,
        wifiPort: (json['wifiPort'] as num?)?.toInt() ?? 9100,
        bluetoothMac: json['bluetoothMac'] as String?,
        bluetoothName: json['bluetoothName'] as String?,
      );

  static String encode(PrinterConfig config) => jsonEncode(config.toJson());
  static PrinterConfig? decode(String? raw) {
    if (raw == null) return null;
    try {
      return PrinterConfig.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
    } catch (_) {
      return null;
    }
  }
}
