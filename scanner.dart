import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'api.dart';
import 'models.dart';
import 'status.dart';

const takerFee = 0.001; // 0.1% per leg

// ============================================
// ==== THRESHOLDS ====
// ============================================

// Cross-exchange spot arbitrage
const minCrossNet   = 0.02;    // 2% minimum
const maxCrossNet   = 0.20;    // 20% maximum
const minCrossLiq   = 500.0;   // $500 minimum depth

// Triangular arbitrage
const minTriNet     = 0.01;    // 1% minimum
const maxTriNet     = 0.20;    // 20% maximum
const minTriLiq     = 500.0;

// Funding arbitrage — per 8h (UNCHANGED)
const minFundSpread = 0.02;
const minFundSingle = 0.02;
const maxFundEdge   = 0.40;

const refreshSeconds = 60;

// Stablecoins — triangular intermediates skip
const _stables = {'USDT', 'USDC', 'BUSD', 'DAI', 'TUSD', 'FDUSD', 'USDD', 'PYUSD'};

// ============================================
// ==== CROSS-EXCHANGE SCAN ====
// ============================================
List<CrossOpp> scanCross(Map<String, Book> books) {
  // Group by full pair name (BTC/USDT, BTC/EUR, ETH/BTC, etc.)
  final pairs = <String, Map<String, Quote>>{};

  books.forEach((ex, b) {
    b.forEach((pair, q) {
      final i = pair.indexOf('/');
      if (i < 1) return;
      final coin = pair.substring(0, i);
      final quote = pair.substring(i + 1);

      // Stable-stable pairs skip (USDT/USDC etc.) — no arbitrage there
      if (_stables.contains(coin) && _stables.contains(quote)) return;

      final m = pairs[pair] ??= {};
      m[ex] = q;
    });
  });

  final out = <CrossOpp>[];
  pairs.forEach((pair, m) {
    if (m.length < 2) return;
    final buy  = m.entries.reduce((a, b) => a.value.ask <= b.value.ask ? a : b);
    final sell = m.entries.reduce((a, b) => a.value.bid >= b.value.bid ? a : b);
    if (buy.key == sell.key) return;

    final net = (sell.value.bid - buy.value.ask) / buy.value.ask - 2 * takerFee;
    final liq = min(buy.value.askQty * buy.value.ask,
                    sell.value.bidQty * sell.value.bid);

    if (net >= minCrossNet && net <= maxCrossNet && liq >= minCrossLiq) {
      out.add(CrossOpp(pair, buy.key, sell.key, buy.value.ask, sell.value.bid,
          net, liq, buy.value.est || sell.value.est));
    }
  });
  return out..sort((a, b) => b.net.compareTo(a.net));
}

// ============================================
// ==== TRIANGULAR SCAN (CORRECT FORMULA) ====
// ============================================
//
// Path A (Forward):  USDT → X → Y → USDT
//   Step 1: Buy X with USDT  → 1 USDT = 1/qx.ask X
//   Step 2: Buy Y with X     → 1 X    = 1/yx.ask Y
//   Step 3: Sell Y for USDT  → 1 Y    = yUsdt.bid USDT
//   Final: yUsdt.bid / (qx.ask × yx.ask)
//
// Path B (Reverse):  USDT → Y → X → USDT
//   Step 1: Buy Y with USDT  → 1 USDT = 1/yUsdt.ask Y
//   Step 2: Sell Y for X     → 1 Y    = yx.bid X
//   Step 3: Sell X for USDT  → 1 X    = qx.bid USDT
//   Final: (qx.bid × yx.bid) / yUsdt.ask
//
List<TriOpp> scanTri(String ex, Book b) {
  final out = <TriOpp>[];
  final seen = <String>{};

  // Step 1: USDT-quoted pairs (X/USDT) — stable base skip
  final usdtPairs = b.entries
      .where((e) => e.key.endsWith('/USDT'))
      .where((e) => !_stables.contains(e.key.split('/')[0]))
      .toList();

  for (final u in usdtPairs) {
    final x = u.key.split('/')[0];        // e.g. BTC, EUR, TRY
    final qx = u.value;                    // X/USDT
    final xUsd = (qx.bid + qx.ask) / 2;

    // Step 2: Y/X pairs — Y ko intermediate banao
    for (final e in b.entries) {
      if (!e.key.endsWith('/$x')) continue;
      final y = e.key.split('/')[0];
      if (y == x) continue;
      if (_stables.contains(y)) continue;    // USDC, DAI skip
      final yx = e.value;                     // Y/X

      // Step 3: Y/USDT pair chahiye
      final yUsdt = b['$y/USDT'];
      if (yUsdt == null) continue;

      // ==== SAHI FORMULA ====
      // Forward: USDT → X → Y → USDT
      final fwd = yUsdt.bid / (qx.ask * yx.ask);

      // Reverse: USDT → Y → X → USDT
      final rev = (qx.bid * yx.bid) / yUsdt.ask;

      final isFwd = fwd >= rev;
      final gross = isFwd ? fwd : rev;

      // 3 legs × 0.1% fee each
      final net = gross * pow(1 - takerFee, 3) - 1;

      // Range check: 1% to 20%
      if (net < minTriNet || net > maxTriNet) continue;

      // Liquidity (in USDT equivalent)
      final liq = isFwd
          ? [
              qx.askQty * qx.ask,
              yx.askQty * yx.ask * xUsd,
              yUsdt.bidQty * yUsdt.bid,
            ].reduce(min)
          : [
              yUsdt.askQty * yUsdt.ask,
              yx.bidQty * yx.bid * xUsd,
              qx.bidQty * qx.bid,
            ].reduce(min);
      if (liq < minTriLiq) continue;

      final path = isFwd
          ? 'USDT → $x → $y → USDT'
          : 'USDT → $y → $x → USDT';

      // Duplicate prevention
      final key = '$ex|${([x, y]..sort()).join("_")}';
      if (!seen.add(key)) continue;

      out.add(TriOpp(ex, path, net, liq,
          qx.est || yx.est || yUsdt.est));
    }
  }
  return out..sort((a, b) => b.net.compareTo(a.net));
}

// ============================================
// ==== FUNDING ARBITRAGE — UNCHANGED ====
// ============================================
List<FundOpp> scanFunding(Map<String, Map<String, double>> f) {
  final coins = <String, Map<String, double>>{};
  f.forEach((ex, m) => m.forEach((c, r) => (coins[c] ??= {})[ex] = r));

  final out = <FundOpp>[];
  coins.forEach((c, m) {
    final hi = m.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final lo = m.entries.reduce((a, b) => a.value <= b.value ? a : b);
    final o = FundOpp(c, hi.key, hi.value, lo.key, lo.value, m);

    final edge = m.length > 1 ? (hi.value - lo.value).abs() : hi.value.abs();
    final minEdge = m.length > 1 ? minFundSpread : minFundSingle;

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