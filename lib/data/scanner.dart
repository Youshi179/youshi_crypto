import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'api.dart';
import 'models.dart';
import 'status.dart';

const takerFee = 0.001; // 0.1% per leg

// ============================================
// ==== THRESHOLDS (User requirement) ====
// ============================================

// Cross-exchange spot arbitrage
const minCrossNet   = 0.03;    // 3% minimum
const maxCrossNet   = 0.20;    // 20% maximum
const minCrossLiq   = 5000.0;  // $5,000 minimum depth

// Triangular arbitrage
const minTriNet     = 0.02;    // 2% minimum
const maxTriNet     = 0.40;    // 40% maximum
const minTriLiq     = 1000.0;

// Funding arbitrage — per 8h
const minFundSpread = 0.02;    // 2% minimum (cross-exchange)
const minFundSingle = 0.02;    // 2% minimum (single exchange)
const maxFundEdge   = 0.40;    // 40% maximum (positive & negative)

const refreshSeconds = 60;

// ============================================
// ==== CROSS-EXCHANGE SCAN ====
// ============================================
List<CrossOpp> scanCross(Map<String, Book> books) {
  final coins = <String, Map<String, Quote>>{};
  books.forEach((ex, b) => b.forEach((p, q) {
        if (!p.endsWith('/USDT') && !p.endsWith('/USDC')) return;
        final m = coins[p.split('/')[0]] ??= {};
        if (p.endsWith('/USDT') || !m.containsKey(ex)) m[ex] = q;
      }));
  final out = <CrossOpp>[];
  coins.forEach((coin, m) {
    if (m.length < 2) return;
    final buy  = m.entries.reduce((a, b) => a.value.ask <= b.value.ask ? a : b);
    final sell = m.entries.reduce((a, b) => a.value.bid >= b.value.bid ? a : b);
    if (buy.key == sell.key) return;
    final net = (sell.value.bid - buy.value.ask) / buy.value.ask - 2 * takerFee;
    final liq = min(buy.value.askQty * buy.value.ask,
                    sell.value.bidQty * sell.value.bid);
    // Saare coins — low-cap bhi
    if (net >= minCrossNet && net <= maxCrossNet && liq >= minCrossLiq) {
      out.add(CrossOpp(coin, buy.key, sell.key, buy.value.ask, sell.value.bid,
          net, liq, buy.value.est || sell.value.est));
    }
  });
  return out..sort((a, b) => b.net.compareTo(a.net));
}

// ============================================
// ==== TRIANGULAR SCAN (Saare pairs, 8 exchanges) ====
// ============================================
List<TriOpp> scanTri(String ex, Book b) {
  final out = <TriOpp>[];
  final seen = <String>{};

  // Har USDT pair ko intermediate maan lo
  final usdtPairs = b.entries
      .where((e) => e.key.endsWith('/USDT'))
      .toList();

  for (final u in usdtPairs) {
    final x = u.key.split('/')[0];
    final qx = u.value;
    final xUsd = (qx.bid + qx.ask) / 2;

    for (final e in b.entries) {
      if (!e.key.endsWith('/$x')) continue;
      final y = e.key.split('/')[0];
      if (y == x || y == 'USDT' || y == 'USDC') continue;
      final yx = e.value;

      final yUsdt = b['$y/USDT'];
      if (yUsdt == null) continue;

      // Path 1 (forward):  USDT → X → Y → USDT
      final fwd = (1 / qx.ask) * yx.bid * yUsdt.bid;

      // Path 2 (reverse):  USDT → Y → X → USDT
      final rev = (1 / yUsdt.ask) * (1 / yx.ask) * qx.bid;

      final isFwd = fwd >= rev;
      final net = (isFwd ? fwd : rev) * pow(1 - takerFee, 3) - 1;

      if (net < minTriNet || net > maxTriNet) continue;

      final liq = isFwd
          ? [
              qx.askQty * qx.ask,
              yx.bidQty * yx.bid * xUsd,
              yUsdt.bidQty * yUsdt.bid,
            ].reduce(min)
          : [
              yUsdt.askQty * yUsdt.ask,
              yx.askQty * yx.ask * xUsd,
              qx.bidQty * qx.bid,
            ].reduce(min);
      if (liq < minTriLiq) continue;

      final path = isFwd
          ? 'USDT → $x → $y → USDT'
          : 'USDT → $y → $x → USDT';

      final key = '$ex|${[x, y]..sort()}';
      if (!seen.add(key)) continue;

      out.add(TriOpp(ex, path, net, liq,
          qx.est || yx.est || yUsdt.est));
    }
  }
  return out..sort((a, b) => b.net.compareTo(a.net));
}

// ============================================
// ==== FUNDING ARBITRAGE SCAN ====
// ============================================
// Detect: highest funding + lowest funding
// Per 8h rate, both positive & negative
// Range: 2% minimum, 40% maximum (absolute value)
List<FundOpp> scanFunding(Map<String, Map<String, double>> f) {
  final coins = <String, Map<String, double>>{};
  f.forEach((ex, m) => m.forEach((c, r) => (coins[c] ??= {})[ex] = r));

  final out = <FundOpp>[];
  coins.forEach((c, m) {
    // Highest funding rate
    final hi = m.entries.reduce((a, b) => a.value >= b.value ? a : b);
    // Lowest funding rate
    final lo = m.entries.reduce((a, b) => a.value <= b.value ? a : b);

    final o = FundOpp(c, hi.key, hi.value, lo.key, lo.value, m);

    // Edge = absolute value (positive & negative dono)
    final edge = m.length > 1 ? (hi.value - lo.value).abs() : hi.value.abs();
    final minEdge = m.length > 1 ? minFundSpread : minFundSingle;

    // 2% se kam skip, 40% se zyada skip
    if (edge >= minEdge && edge <= maxFundEdge) {
      out.add(o);
    }
  });
  return out..sort((a, b) => b.edge.compareTo(a.edge));
}

// ============================================
// ==== SCANNER CONTROLLER ====
// ============================================
class ScannerController extends ChangeNotifier {
  Scan? data;
  bool loading = false;
  Timer? _timer;

  void start() {
    refresh();
    _timer = Timer.periodic(const Duration(seconds: refreshSeconds), (_) => refresh());
  }

  Future<void> refresh() async {
    if (loading) {
      return;
    }
    loading = true;
    notifyListeners();
    final errs = <String>[];
    final books = <String, Book>{};
    final fund  = <String, Map<String, double>>{};
    final wallet = <String, Map<String, WS>>{};

    Future<void> run(String n, Future<void> Function() f) async {
      try {
        await f();
      } catch (_) {
        errs.add(n);
      }
    }

    await Future.wait([
      for (final e in spotApis.entries)
        run(e.key, () async => books[e.key] = await e.value()),
      for (final e in fundApis.entries)
        run('${e.key} (F)', () async => fund[e.key] = await e.value()),
      for (final e in walletApis.entries)
        run('${e.key} (W)', () async {
          final k = await loadKeys(e.key);
          if (!publicWallet.contains(e.key) &&
              (k['key']!.isEmpty || k['secret']!.isEmpty)) {
            return;
          }
          wallet[e.key] = await e.value(k);
        }),
    ]);

    final tri = <TriOpp>[
      for (final e in books.entries) ...scanTri(e.key, e.value)
    ]..sort((a, b) => b.net.compareTo(a.net));

    data = Scan(scanCross(books), tri, scanFunding(fund), errs,
        DateTime.now(), wallet);
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}