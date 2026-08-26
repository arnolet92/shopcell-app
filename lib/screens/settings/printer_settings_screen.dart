import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../core/theme.dart';
import '../../models/printer_config.dart';
import '../../services/pdf_ticket_builder.dart';
import '../../services/printer_service.dart';
import '../../services/ticket_builder.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/inline_field.dart';

/// Paramètres de l'imprimante ticket (WiFi ou Bluetooth), stockés en base
/// locale (`LocalDb.keyPrinterConfig`), accessible depuis le sidebar.
class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  PrinterType _type = PrinterType.wifi;
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '9100');

  List<BluetoothInfo> _pairedDevices = [];
  BluetoothInfo? _selectedDevice;
  bool _loadingDevices = false;

  bool _saving = false;
  bool _testing = false;
  String? _message;
  bool _messageIsError = false;

  bool _a4Enabled = false;
  bool _testingA4 = false;
  String? _a4Message;
  bool _a4MessageIsError = false;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
    _loadA4();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrent() async {
    final cfg = await PrinterService.instance.config;
    if (cfg == null || !mounted) return;
    setState(() {
      _type = cfg.type;
      _ipController.text = cfg.wifiIp ?? '';
      _portController.text = cfg.wifiPort.toString();
    });
    if (cfg.type == PrinterType.bluetooth && cfg.bluetoothMac != null) {
      setState(() => _selectedDevice = BluetoothInfo(name: cfg.bluetoothName ?? cfg.bluetoothMac!, macAdress: cfg.bluetoothMac!));
    }
  }

  Future<void> _scanPaired() async {
    setState(() {
      _loadingDevices = true;
      _message = null;
    });
    final status = await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
    final granted = status.values.every((s) => s.isGranted);
    if (!granted) {
      setState(() {
        _loadingDevices = false;
        _message = "Autorisation Bluetooth refusée.";
        _messageIsError = true;
      });
      return;
    }
    try {
      final devices = await PrinterService.instance.pairedBluetoothPrinters();
      if (!mounted) return;
      setState(() {
        _pairedDevices = devices;
        _loadingDevices = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingDevices = false;
        _message = "Impossible de lister les imprimantes appairées : $e";
        _messageIsError = true;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _message = null;
    });

    final config = _type == PrinterType.wifi
        ? PrinterConfig(
            type: PrinterType.wifi,
            wifiIp: _ipController.text.trim(),
            wifiPort: int.tryParse(_portController.text.trim()) ?? 9100,
          )
        : PrinterConfig(
            type: PrinterType.bluetooth,
            bluetoothMac: _selectedDevice?.macAdress,
            bluetoothName: _selectedDevice?.name,
          );

    await PrinterService.instance.saveConfig(config);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _message = 'Configuration enregistrée.';
      _messageIsError = false;
    });
  }

  Future<void> _testPrint() async {
    setState(() {
      _testing = true;
      _message = null;
    });
    await _save();
    final bytes = await TicketBuilder.buildSaleReceipt(
      shopName: 'ShopCell',
      cashierName: 'Test',
      lines: const [],
      total: 0,
    );
    final result = await PrinterService.instance.printBytes(bytes);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _message = result.success ? 'Ticket de test envoyé avec succès.' : result.message;
      _messageIsError = !result.success;
    });
  }

  Future<void> _loadA4() async {
    final enabled = await PrinterService.instance.isA4Enabled;
    if (!mounted) return;
    setState(() => _a4Enabled = enabled);
  }

  Future<void> _toggleA4(bool value) async {
    setState(() => _a4Enabled = value);
    await PrinterService.instance.setA4Enabled(value);
  }

  Future<void> _testPrintA4() async {
    setState(() {
      _testingA4 = true;
      _a4Message = null;
    });
    final doc = await PdfTicketBuilder.buildSaleReceiptA4(
      shopName: 'ShopCell',
      numeroFacture: 'TEST-0001',
      clientNom: 'Client de test',
      lines: const [],
      total: 0,
    );
    final result = await PrinterService.instance.printPdf(doc, docName: 'Test A4');
    if (!mounted) return;
    setState(() {
      _testingA4 = false;
      _a4Message = result.success ? 'Document envoyé à l\'imprimante.' : result.message;
      _a4MessageIsError = !result.success;
    });
  }

  /// Repli si le sélecteur d'imprimantes intégré ne trouve pas l'imprimante
  /// (souci de découverte réseau selon les appareils) : partage le PDF vers
  /// une autre application (Google Drive, lecteur PDF...) où elle est déjà
  /// détectée.
  Future<void> _shareTestA4() async {
    setState(() {
      _testingA4 = true;
      _a4Message = null;
    });
    final doc = await PdfTicketBuilder.buildSaleReceiptA4(
      shopName: 'ShopCell',
      numeroFacture: 'TEST-0001',
      clientNom: 'Client de test',
      lines: const [],
      total: 0,
    );
    final result = await PrinterService.instance.sharePdf(doc, filename: 'test_a4.pdf');
    if (!mounted) return;
    setState(() {
      _testingA4 = false;
      if (!result.success && result.message != null) {
        _a4Message = result.message;
        _a4MessageIsError = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        title: Text('Imprimante ticket', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: _TypeChip(
                    icon: Icons.wifi_rounded,
                    label: 'WiFi',
                    selected: _type == PrinterType.wifi,
                    onTap: () => setState(() => _type = PrinterType.wifi),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TypeChip(
                    icon: Icons.bluetooth_rounded,
                    label: 'Bluetooth',
                    selected: _type == PrinterType.bluetooth,
                    onTap: () => setState(() => _type = PrinterType.bluetooth),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            if (_type == PrinterType.wifi) ...[
              InlineField(label: 'Adresse IP de l\'imprimante', controller: _ipController, prefixIcon: Icons.router_rounded, keyboardType: TextInputType.number),
              const SizedBox(height: 20),
              InlineField(label: 'Port', controller: _portController, prefixIcon: Icons.numbers_rounded, keyboardType: TextInputType.number),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedDevice != null ? '${_selectedDevice!.name} (${_selectedDevice!.macAdress})' : 'Aucune imprimante sélectionnée',
                      style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 13.5),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadingDevices ? null : _scanPaired,
                    child: _loadingDevices
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight))
                        : const Text('Rechercher', style: TextStyle(color: AppColors.accentLight)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ..._pairedDevices.map(
                (d) => RadioListTile<String>(
                  value: d.macAdress,
                  groupValue: _selectedDevice?.macAdress,
                  onChanged: (_) => setState(() => _selectedDevice = d),
                  activeColor: AppColors.accent,
                  contentPadding: EdgeInsets.zero,
                  title: Text(d.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5)),
                  subtitle: Text(d.macAdress, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ),
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(_message!, style: TextStyle(color: _messageIsError ? AppColors.red : AppColors.green, fontSize: 13)),
            ],
            const SizedBox(height: 28),
            GradientButton(label: 'Enregistrer', icon: Icons.save_rounded, loading: _saving, onPressed: _save),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _testing ? null : _testPrint,
                icon: _testing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight))
                    : const Icon(Icons.print_rounded, size: 18, color: AppColors.accentLight),
                label: const Text('Imprimer un ticket de test', style: TextStyle(color: AppColors.accentLight)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.borderAccent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Divider(color: AppColors.border),
            const SizedBox(height: 20),
            Row(
              children: [
                const Icon(Icons.description_rounded, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text('Imprimante A4 (feuille)', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "Pour une imprimante classique (jet d'encre/laser, ex: Canon G3800), pas une imprimante ticket. "
              "L'impression passe par le système Android : vérifiez qu'un service d'impression (Mopria, ou l'app du fabricant) est installé et que l'imprimante est sur le même réseau WiFi.",
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Proposer l\'impression A4 après une vente', style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary)),
                value: _a4Enabled,
                activeThumbColor: AppColors.accent,
                onChanged: _toggleA4,
              ),
            ),
            if (_a4Message != null) ...[
              const SizedBox(height: 8),
              Text(_a4Message!, style: TextStyle(color: _a4MessageIsError ? AppColors.red : AppColors.green, fontSize: 13)),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _testingA4 ? null : _testPrintA4,
                icon: _testingA4
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight))
                    : const Icon(Icons.print_rounded, size: 18, color: AppColors.accentLight),
                label: const Text('Imprimer un document A4 de test', style: TextStyle(color: AppColors.accentLight)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.borderAccent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "L'imprimante n'apparaît pas dans la liste ? Essayez plutôt :",
              style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _testingA4 ? null : _shareTestA4,
                icon: const Icon(Icons.share_rounded, size: 18, color: AppColors.textSecondary),
                label: const Text('Partager le PDF (autre application)', style: TextStyle(color: AppColors.textSecondary)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentGlow : AppColors.bgCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? AppColors.borderAccent : AppColors.border),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? AppColors.accentLight : AppColors.textSecondary, size: 22),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(color: selected ? AppColors.accentLight : AppColors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
