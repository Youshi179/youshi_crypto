import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

const _quotes = ['USDT', 'USDC', 'USD', 'EUR', 'GBP', 'TRY', 'BRL', 'AUD', 'DAI', 'FDUSD', 'BTC', 'ETH', 'BNB'];
const _timeout = Duration(seconds: 20);
int _ts() => DateTime.now().millisecondsSinceEpoch;

Future<dynamic> _get(String url) async {
  final r = await http.get(Uri.parse(url)).timeout(_timeout);
  if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
  return jsonDecode(r.body);
}

double _d(dynamic v) => double.tryParse('${v ?? ''}') ?? 0;

String? _pair(String s) {
  for (final q in _quotes) {
    if (s.endsWith(q) && s.length > q.length) return '${s.substring(0, s.length - q.length)}/$q';
  }
  return null;
}

String? _sp(String s) {
  final i = s.contains('-') ? s.indexOf('-') : s.indexOf('_');
  if (i < 1) return null;
  final q = s.substring(i + 1);
  return _quotes.contains(q) ? '${s.substring(0, i)}/$q' : null;
}

void _put(Book b, String? p, dynamic bid, dynamic bq, dynamic ask, dynamic aq) {
  if (p == null) return;
  final q = Quote(_d(bid), _d(bq), _d(ask), _d(aq));
  if (q.ok && q.bidQty > 0 && q.askQty > 0) b[p] = q;
}

void _putEst(Book b, String? p, dynamic bid, dynamic ask, dynamic vol) {
  final bd = _d(bid), ak = _d(ask), usd = _d(vol) / 288;
  if (p == null || bd <= 0 || ak <= 0 || usd <= 0) return;
  final qty = usd / ((bd + ak) / 2);
  b[p] = Quote(bd, qty, ak, qty, true);
}

Future<Book> _binanceLike(String url) async {
  final b = <String, Quote>{};
  for (final e in await _get(url) as List) {
    _put(b, _pair(e['symbol']), e['bidPrice'], e['bidQty'], e['askPrice'], e['askQty']);
  }
  return b;
}

final Map<String, Future<Book> Function()> spotApis = {
  'Binance': () => _binanceLike('https://api.binance.com/api/v3/ticker/bookTicker'),
  'MEXC': () => _binanceLike('https://api.mexc.com/api/v3/ticker/bookTicker'),
  'Bybit': () async {
    final b = <String, Quote>{};
    final j = await _get('https://api.bybit.com/v5/market/tickers?category=spot');
    for (final e in j['result']['list']) {
      _put(b, _pair(e['symbol']), e['bid1Price'], e['bid1Size'], e['ask1Price'], e['ask1Size']);
    }
    return b;
  },
  'OKX': () async {
    final b = <String, Quote>{};
    final j = await _get('https://www.okx.cab/api/v5/market/tickers?instType=SPOT');
    for (final e in j['data']) {
      _put(b, _sp(e['instId']), e['bidPx'], e['bidSz'], e['askPx'], e['askSz']);
    }
    return b;
  },
  'Bitget': () async {
    final b = <String, Quote>{};
    final j = await _get('https://api.bitget.com/api/v2/spot/market/tickers');
    for (final e in j['data']) {
      _put(b, _pair(e['symbol']), e['bidPr'], e['bidSz'], e['askPr'], e['askSz']);
    }
    return b;
  },
  'KuCoin': () async {
    final b = <String, Quote>{};
    final j = await _get('https://api.kucoin.com/api/v1/market/allTickers');
    for (final e in j['data']['ticker']) {
      _putEst(b, _sp(e['symbol']), e['buy'], e['sell'], e['volValue']);
    }
    return b;
  },
  'Gate': () async {
    final b = <String, Quote>{};
    for (final e in await _get('https://api.gateio.ws/api/v4/spot/tickers') as List) {
      _putEst(b, _sp(e['currency_pair']), e['highest_bid'], e['lowest_ask'], e['quote_volume']);
    }
    return b;
  },
  'BingX': () async {
    final b = <String, Quote>{};
    final j = await _get('https://open-api.bingx.com/openApi/spot/v1/ticker/24hr?timestamp=${_ts()}');
    for (final e in j['data']) {
      final p = _sp(e['symbol']);
      if (e['bidQty'] != null && e['askQty'] != null) {
        _put(b, p, e['bidPrice'], e['bidQty'], e['askPrice'], e['askQty']);
      } else {
        _putEst(b, p, e['bidPrice'], e['askPrice'], e['quoteVolume']);
      }
    }
    return b;
  },
};

String _coin(String c) {
  c = c.replaceFirst(RegExp(r'^(1000000|10000|1000)'), '');
  if (c.length > 1 && c.startsWith('k') && c[1] == c[1].toUpperCase()) c = c.substring(1);
  return (c == 'XBT' ? 'BTC' : c).toUpperCase();
}

double _n8(double rate, double hours) => hours <= 0 ? rate : rate * 8 / hours;
String _cut(String s, int n) => s.substring(0, s.length - n);

final Map<String, Future<Map<String, double>> Function()> fundApis = {
  'Binance': () async {
    final m = <String, double>{};
    for (final e in await _get('https://fapi.binance.com/fapi/v1/premiumIndex') as List) {
      final s = e['symbol'] as String;
      if (s.endsWith('USDT') && e['lastFundingRate'] != '') m[_coin(_cut(s, 4))] = _d(e['lastFundingRate']);
    }
    return m;
  },
  'Bybit': () async {
    final m = <String, double>{};
    final j = await _get('https://api.bybit.com/v5/market/tickers?category=linear');
    for (final e in j['result']['list']) {
      final s = e['symbol'] as String;
      if (!s.endsWith('USDT') || '${e['fundingRate']}'.isEmpty) continue;
      final h = _d(e['fundingIntervalHour']);
      m[_coin(_cut(s, 4))] = _n8(_d(e['fundingRate']), h == 0 ? 8 : h);
    }
    return m;
  },
  'OKX': () async {
    final m = <String, double>{};
    final j = await _get('https://www.okx.cab/api/v5/public/funding-rate?instId=ANY');
    for (final e in j['data']) {
      final id = e['instId'] as String;
      if (!id.endsWith('-USDT-SWAP')) continue;
      final h = (_d(e['nextFundingTime']) - _d(e['fundingTime'])) / 3600000;
      m[_coin(id.split('-')[0])] = _n8(_d(e['fundingRate']), h <= 0 ? 8 : h);
    }
    return m;
  },
  'Bitget': () async {
    final m = <String, double>{};
    final j = await _get('https://api.bitget.com/api/v2/mix/market/tickers?productType=USDT-FUTURES');
    for (final e in j['data']) {
      final s = e['symbol'] as String;
      if (s.endsWith('USDT') && '${e['fundingRate']}'.isNotEmpty) m[_coin(_cut(s, 4))] = _d(e['fundingRate']);
    }
    return m;
  },
  'KuCoin': () async {
    final m = <String, double>{};
    final j = await _get('https://api-futures.kucoin.com/api/v1/contracts/active');
    for (final e in j['data']) {
      if (e['quoteCurrency'] != 'USDT' || e['fundingFeeRate'] == null) continue;
      m[_coin(e['baseCurrency'])] = _n8(_d(e['fundingFeeRate']), _d(e['fundingRateGranularity']) / 3600000);
    }
    return m;
  },
  'MEXC': () async {
    final m = <String, double>{};
    final j = await _get('https://contract.mexc.com/api/v1/contract/funding_rate');
    for (final e in j['data']) {
      final s = e['symbol'] as String;
      if (s.endsWith('_USDT')) m[_coin(s.split('_')[0])] = _n8(_d(e['fundingRate']), _d(e['collectCycle']));
    }
    return m;
  },
  'BingX': () async {
    final m = <String, double>{};
    final j = await _get('https://open-api.bingx.com/openApi/swap/v2/quote/premiumIndex?timestamp=${_ts()}');
    final d = j['data'];
    for (final e in (d is List ? d : [d])) {
      final s = e['symbol'] as String;
      if (s.endsWith('-USDT') && e['lastFundingRate'] != null) m[_coin(s.split('-')[0])] = _d(e['lastFundingRate']);
    }
    return m;
  },
  'Gate': () async {
    final m = <String, double>{};
    for (final e in await _get('https://api.gateio.ws/api/v4/futures/usdt/contracts') as List) {
      final n = e['name'] as String;
      if (!n.endsWith('_USDT')) continue;
      final h = _d(e['funding_interval']) / 3600;
      m[_coin(n.split('_')[0])] = _n8(_d(e['funding_rate']), h == 0 ? 8 : h);
    }
    return m;
  },
};