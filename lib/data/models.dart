class Quote {
  final double bid, bidQty, ask, askQty;
  final bool est;
  const Quote(this.bid, this.bidQty, this.ask, this.askQty, [this.est = false]);
  bool get ok => bid > 0 && ask > 0;
}

enum WalletState { open, closed, unknown }

typedef WS = ({bool dep, bool wd, bool known});
typedef Book = Map<String, Quote>;

class CrossOpp {
  final String coin, buyEx, sellEx;
  final double buy, sell, net, liq;
  final bool est;
  const CrossOpp(this.coin, this.buyEx, this.sellEx, this.buy, this.sell,
      this.net, this.liq, this.est);
}

class TriOpp {
  final String ex, path;
  final double net, liq;
  final bool est;
  const TriOpp(this.ex, this.path, this.net, this.liq, this.est);
}

class FundOpp {
  final String coin, hiEx, loEx;
  final double hi, lo;
  final Map<String, double> all;
  const FundOpp(this.coin, this.hiEx, this.hi, this.loEx, this.lo, this.all);

  double get spread => (hi - lo).abs();
  bool   get single => hiEx == loEx;
  double get edge   => single ? hi.abs() : spread;

  double profitPer8h(double capital) => capital * edge;
  double profitDaily(double capital) => profitPer8h(capital) * 3;
  double profitWeekly(double capital) => profitPer8h(capital) * 21;
  double profitMonthly(double capital) => profitPer8h(capital) * 90;
  double apr(double capital) =>
      capital == 0 ? 0 : (profitDaily(capital) / capital) * 365 * 100;

  String get strategy => single
      ? (hi > 0
          ? 'Single-Exchange: SHORT perp + LONG spot'
          : 'Single-Exchange: LONG perp + SHORT spot')
      : 'Cross-Exchange: SHORT on $hiEx + LONG on $loEx';

  String get hiLoLabel =>
      'HIGH ${(hi * 100).toStringAsFixed(4)}% ($hiEx)  •  LOW ${(lo * 100).toStringAsFixed(4)}% ($loEx)';

  String get hint => single
      ? (hi > 0 ? 'Longs pay you (shorts receive funding)' : 'Shorts pay you (longs receive funding)')
      : 'Dono exchanges par opposite positions open karo';
}

class Scan {
  final List<CrossOpp> cross;
  final List<TriOpp> tri;
  final List<FundOpp> fund;
  final List<String> errors;
  final DateTime time;
  final Map<String, Map<String, WS>> wallet;
  const Scan(this.cross, this.tri, this.fund, this.errors, this.time, this.wallet);
}