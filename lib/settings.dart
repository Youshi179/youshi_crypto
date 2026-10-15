import 'package:flutter/material.dart';
import 'data/status.dart';
import 'main.dart' show bg1, bg2, mint, amber, pink, gMain;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsPage> {
  final keyed = ['Binance', 'OKX', 'Bybit', 'MEXC', 'BingX'];
  final publicEx = ['KuCoin', 'Gate', 'Bitget'];

  final c = {
    for (final e in ['Binance', 'OKX', 'Bybit', 'MEXC', 'BingX'])
      e: {for (final f in ['key', 'secret', 'pass']) f: TextEditingController()}
  };

  @override
  void initState() {
    super.initState();
    for (final e in keyed) {
      loadKeys(e).then((v) {
        v.forEach((f, t) => c[e]![f]!.text = t);
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    for (final m in c.values) {
      for (final t in m.values) {
        t.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _save() async {
    for (final e in keyed) {
      await saveKeys(e, {for (final f in c[e]!.entries) f.key: f.value.text});
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _clear(String ex) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: bg2,
        title: Text('$ex ki API key delete karein?'),
        content: const Text('Yeh action undo nahi ho sakta.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: pink))),
        ],
      ),
    );
    if (confirm != true) return;
    for (final f in c[ex]!.keys) {
     c[ex]![f]!.clear();
    }
    await saveKeys(ex, {for (final f in c[ex]!.keys) f: ''});
    if (mounted) setState(() {});
  }

  Widget _field(String ex, String f, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c[ex]![f],
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
              labelText: label,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
        ),
      );

  bool _hasKey(String ex) => c[ex]!['key']!.text.isNotEmpty;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: bg1,
        appBar: AppBar(
          backgroundColor: bg1,
          title: const Text('API Management'),
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: amber.withAlpha(30), borderRadius: BorderRadius.circular(14)),
            child: const Text(
              'Sirf READ-ONLY key banao. Trade aur Withdraw permission kabhi ON mat karo. Ho sake toh IP whitelist lagao.\n\n'
              'Keys sirf is phone ki secure storage mein rehti hain, kahin upload nahi hoti.\n\n'
              'KuCoin, Gate, Bitget ko key ki zaroorat NAHI — unka wallet status automatic aata hai.',
              style: TextStyle(fontSize: 12.5, height: 1.45),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Keyed Exchanges (API key chahiye)',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 8),
          for (final ex in keyed)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                  color: Colors.white.withAlpha(13),
                  borderRadius: BorderRadius.circular(16)),
              child: ExpansionTile(
                shape: const Border(),
                leading: Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                      color: _hasKey(ex) ? mint : Colors.white30,
                      shape: BoxShape.circle),
                ),
                title: Text(ex, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(
                  _hasKey(ex) ? 'Key saved' : 'Key nahi lagi',
                  style: TextStyle(fontSize: 11.5,
                      color: _hasKey(ex) ? mint : Colors.white38),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                children: [
                  _field(ex, 'key', 'API Key'),
                  _field(ex, 'secret', 'API Secret'),
                  if (ex == 'OKX') _field(ex, 'pass', 'Passphrase'),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _hasKey(ex) ? () => _clear(ex) : null,
                      icon: const Icon(Icons.delete_outline_rounded, color: pink, size: 18),
                      label: const Text('Remove Key',
                          style: TextStyle(color: pink, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          const Text('Public Exchanges (bina key)',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 8),
          for (final ex in publicEx)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: mint.withAlpha(20),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: mint.withAlpha(60))),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded, color: mint, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('$ex — wallet status auto-detect',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          const SizedBox(height: 20),
          InkWell(
            onTap: _save,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  gradient: gMain, borderRadius: BorderRadius.circular(14)),
              child: const Text('Save & Refresh',
                  style: TextStyle(color: Colors.black,
                      fontWeight: FontWeight.w900, fontSize: 15)),
            ),
          ),
        ]),
      );
}