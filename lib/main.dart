import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'data/models.dart';
import 'data/scanner.dart';
import 'settings.dart';

const bg1 = Color(0xFF070A14), bg2 = Color(0xFF160B33);
const mint = Color(0xFF2EF2B4), cyan = Color(0xFF35C8FF), violet = Color(0xFF8B5CF6);
const pink = Color(0xFFFF5C8A), amber = Color(0xFFFFB84D);
const gMain = LinearGradient(colors: [mint, cyan]);
const gHot = LinearGradient(colors: [pink, amber]);
const exColors = {
  'Binance': Color(0xFFF3BA2F), 'OKX': Color(0xFFE8E8E8), 'Bybit': Color(0xFFFFA11A),
  'Bitget': Color(0xFF00F0FF), 'KuCoin': Color(0xFF24AE8F), 'MEXC': Color(0xFF8E6CFF),
  'BingX': Color(0xFF4D7CFF), 'Gate': Color(0xFFFF5C8A),
};

void main() => runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Youshi Crypto',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: bg1,
        colorScheme: const ColorScheme.dark(primary: mint, surface: bg2),
      ),
      home: const Home(),
    ));

String px(double p) => p >= 1 ? p.toStringAsFixed(4) : p >= 0.0001 ? p.toStringAsFixed(6) : p.toStringAsFixed(10);
String pct(double v) => '${(v * 100).toStringAsFixed(3)}%';
String usd(double v) => '\$${v.toStringAsFixed(0)}';

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final ctrl = ScannerController()..start();
  String q = '';
  bool okOnly = false;
  bool _m(String s) => q.isEmpty || s.toUpperCase().contains(q);

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          body: Container(
            decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [bg1, bg2])),
            child: SafeArea(
              child: ListenableBuilder(
                listenable: ctrl,
                builder: (context, _) {
                  final d = ctrl.data;
                  return Column(children: [
                    _header(),
                    _search(),
                    _tabs(d),
                    if (d != null) ...[_progress(d), _status(d)],
                    Expanded(
                      child: d == null
                          ? _loading()
                          : TabBarView(children: [
                              _list<CrossOpp>(d.cross.where((o) => _m(o.coin) && !(okOnly && _walletStatus(d, o).state == WalletState.closed)).toList(), _cross),
                              _list<TriOpp>(d.tri.where((o) => _m(o.path) || _m(o.ex)).toList(), _tri),
                              _list<FundOpp>(d.fund.where((o) => _m(o.coin)).toList(), _fund),
                            ]),
                    ),
                  ]);
                },
              ),
            ),
          ),
        ),
      );

  ({WalletState state, String msg}) _walletStatus(Scan d, CrossOpp o) {
    final w = d.wallet[o.buyEx]?[o.coin];
    final x = d.wallet[o.sellEx]?[o.coin];
    if (w == null && x == null) {
      return (state: WalletState.unknown,
              msg: 'Wallet status unknown (API key add karo)');
    }
    final wOk = w == null ? true : (w.known && w.wd);
    final xOk = x == null ? true : (x.known && x.dep);
    if (!wOk && w.known) {
      return (state: WalletState.closed,
              msg: '${o.buyEx} par ${o.coin} WITHDRAWAL CLOSED');
    }
    if (!xOk && x.known) {
      return (state: WalletState.closed,
              msg: '${o.sellEx} par ${o.coin} DEPOSIT CLOSED');
    }
    if (w?.known == false || x?.known == false) {
      return (state: WalletState.unknown,
              msg: 'Partial data — ${o.buyEx}/${o.sellEx}');
    }
    return (state: WalletState.open,
            msg: 'Wallet OPEN: withdraw ${o.buyEx} → deposit ${o.sellEx}');
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [violet, cyan]), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.bolt_rounded, size: 22, color: Colors.white),
          ),
          const SizedBox(width: 10),
          ShaderMask(
            shaderCallback: (r) => gMain.createShader(r),
            child: const Text('Youshi Crypto',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Wallet OK only',
            icon: Icon(Icons.verified_rounded, color: okOnly ? mint : Colors.white54),
            onPressed: () => setState(() => okOnly = !okOnly),
          ),
          IconButton(
            tooltip: 'API keys',
            icon: const Icon(Icons.vpn_key_rounded),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
              ctrl.refresh();
            },
          ),
          ctrl.loading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: mint)))
              : IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: ctrl.refresh),
        ]),
      );

  Widget _search() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: TextField(
          onChanged: (v) => setState(() => q = v.trim().toUpperCase()),
          decoration: InputDecoration(
            hintText: 'Coin search (PEPE, WIF, BTC...)',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            filled: true,
            fillColor: Colors.white.withAlpha(14),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
      );

  Widget _tabs(Scan? d) => Container(
        margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Colors.white.withAlpha(14), borderRadius: BorderRadius.circular(16)),
        child: TabBar(
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          indicator: BoxDecoration(gradient: gMain, borderRadius: BorderRadius.circular(12)),
          tabs: [
            Tab(height: 38, text: 'Cross · ${d?.cross.length ?? 0}'),
            Tab(height: 38, text: 'Tri · ${d?.tri.length ?? 0}'),
            Tab(height: 38, text: 'Funding · ${d?.fund.length ?? 0}'),
          ],
        ),
      );

  Widget _progress(Scan d) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            key: ValueKey(d.time),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(seconds: refreshSeconds),
            builder: (_, v, __) => LinearProgressIndicator(
                value: v, minHeight: 3, color: violet, backgroundColor: Colors.white.withAlpha(18)),
          ),
        ),
      );

  Widget _status(Scan d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = d.time;
    final spotErr = d.errors.where((e) => !e.contains('(')).length;
    final fundErr = d.errors.where((e) => e.contains('(F)')).length;
    final walErr  = d.errors.where((e) => e.contains('(W)')).length;
    final allOk = spotErr == 0 && fundErr == 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '${8 - spotErr}/8 spot • ${8 - fundErr}/8 funding'
          '${walErr > 0 ? ' • $walErr wallet err' : ''}'
          ' • ${two(t.hour)}:${two(t.minute)}:${two(t.second)}'
          '${allOk ? '' : '  ⚠ ${d.errors.join(', ')}'}',
          style: TextStyle(fontSize: 11,
              color: allOk ? Colors.white54 : amber),
        ),
      ),
    );
  }

  Widget _loading() => const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: mint),
          SizedBox(height: 16),
          Text('8 exchanges scan ho rahi hain...', style: TextStyle(color: Colors.white60)),
        ]),
      );

  Widget _list<T>(List<T> items, Widget Function(T, int) b) => items.isEmpty
      ? Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: const [
            Icon(Icons.radar_rounded, size: 56, color: Colors.white24),
            SizedBox(height: 8),
            Text('Abhi koi opportunity nahi mili', style: TextStyle(color: Colors.white54)),
          ]),
        )
      : RefreshIndicator(
          color: mint,
          backgroundColor: bg2,
          onRefresh: ctrl.refresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: items.length > 200 ? 200 : items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => b(items[i], i),
          ),
        );

  Widget _ex(String n, [String? tag]) {
    final c = exColors[n] ?? Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: c.withAlpha(36), borderRadius: BorderRadius.circular(8), border: Border.all(color: c.withAlpha(110))),
      child: Text(tag == null ? n : '$tag $n',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
    );
  }

  static const _arrow = Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.white38);

  Widget _card({
    required Key k,
    required int i,
    required String title,
    required List<Widget> chips,
    required String l1,
    String? l2,
    Color? l2c,
    required String badge,
    bool hot = false,
    VoidCallback? onTap,
  }) =>
      _Pop(
        key: k,
        i: i,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onTap();
                  },
            child: Ink(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(13),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: hot ? pink.withAlpha(110) : Colors.white.withAlpha(22)),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: chips),
                    const SizedBox(height: 6),
                    Text(l1, style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
                    if (l2 != null) Text(l2, style: TextStyle(fontSize: 11.5, color: l2c ?? Colors.white38)),
                  ]),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                  decoration: BoxDecoration(gradient: hot ? gHot : gMain, borderRadius: BorderRadius.circular(12)),
                  child: Text(badge, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black)),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _cross(CrossOpp o, int i) {
    final d = ctrl.data!;
    final s = _walletStatus(d, o);
    final color = s.state == WalletState.open
        ? mint
        : s.state == WalletState.closed
            ? pink
            : amber;
    return _card(
      k: ValueKey('c${o.coin}'),
      i: i,
      title: o.coin,
      chips: [_ex(o.buyEx, 'BUY'), _arrow, _ex(o.sellEx, 'SELL')],
      l1: 'Buy ${px(o.buy)}  →  Sell ${px(o.sell)}',
      l2: 'Liquidity ${o.est ? '~' : ''}${usd(o.liq)}\n${s.msg}',
      l2c: color,
      badge: '+${pct(o.net)}',
      hot: s.state == WalletState.closed || o.net > 0.1,
    );
  }

  Widget _tri(TriOpp o, int i) => _card(
        k: ValueKey('t${o.ex}${o.path}'),
        i: i,
        title: o.path.split(' → ')[1],
        chips: [_ex(o.ex)],
        l1: o.path,
        l2: 'Liquidity ${o.est ? '~' : ''}${usd(o.liq)} • 3 legs fees minus',
        badge: '+${pct(o.net)}',
        hot: o.net > 0.05,
      );

  Widget _fund(FundOpp o, int i) => _card(
        k: ValueKey('f${o.coin}'),
        i: i,
        title: o.coin,
        chips: o.single
            ? [_ex(o.hiEx, o.hi > 0 ? 'SHORT' : 'LONG')]
            : [_ex(o.hiEx, 'SHORT ${pct(o.hi)}'), _arrow, _ex(o.loEx, 'LONG ${pct(o.lo)}')],
        l1: o.hiLoLabel,
        l2: '${o.strategy}\n${o.hint} • tap = calculator',
        badge: pct(o.edge),
        hot: o.edge >= 0.05,
        onTap: () => _calc(o),
      );

  void _calc(FundOpp o) {
    final tc = TextEditingController(text: '1000');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bg2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) {
          final cap = double.tryParse(tc.text) ?? 0;
          final per8 = o.profitPer8h(cap);
          final day  = o.profitDaily(cap);
          final wk   = o.profitWeekly(cap);
          final mo   = o.profitMonthly(cap);
          final apr  = o.apr(cap);
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${o.coin} • Funding Calculator',
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(o.strategy, style: const TextStyle(color: mint, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(o.hiLoLabel, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 14),
                TextField(
                  controller: tc,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: 'Capital (USDT)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
                  onChanged: (_) => set(() {}),
                ),
                const SizedBox(height: 16),
                _profitRow('Per 8 hours', per8),
                _profitRow('Daily (x3)', day),
                _profitRow('Weekly (x21)', wk),
                _profitRow('Monthly (x90)', mo),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(gradient: gMain,
                      borderRadius: BorderRadius.circular(16)),
                  child: Text('APR ~ ${apr.toStringAsFixed(2)}%',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black,
                          fontWeight: FontWeight.w900, fontSize: 17)),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Yeh gross profit hai. Actual profit mein fees, slippage, aur funding rate change shamil nahi.',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _profitRow(String label, double val) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white70))),
          Text('\$${val.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
      );
}

class _Pop extends StatelessWidget {
  final int i;
  final Widget child;
  const _Pop({super.key, required this.i, required this.child});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 280 + (i > 10 ? 10 : i) * 40),
        curve: Curves.easeOutCubic,
        builder: (_, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 18 * (1 - v)), child: c)),
        child: child,
      );
}