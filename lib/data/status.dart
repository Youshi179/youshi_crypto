import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'models.dart';

const _store = FlutterSecureStorage();
const keyedEx = ['Binance', 'OKX', 'Bybit', 'MEXC', 'BingX'];
const publicWallet = {'KuCoin', 'Gate', 'Bitget'};

Future<Map<String, String>> loadKeys(String ex) async => {
      for (final f in ['key', 'secret', 'pass']) f: await _store.read(key: '$ex.$f') ?? '',
    };

Future<void> saveKeys(String ex, Map<String, String> v) async {
  for (final e in v.entries) {
    await _store.write(key: '$ex.${e.key}', value: e.value.trim());
  }
}

int _now() => DateTime.now().millisecondsSinceEpoch;
String _hmac(String msg, String secret) => Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(msg)).toString();
bool _b(dynamic v) => v == true || '$v' == 'true' || '$v' == '1';

Future<dynamic> _j(String url, [Map<String, String>? h]) async {
  final r = await http.get(Uri.parse(url), headers: h).timeout(const Duration(seconds: 20));
  if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
  return jsonDecode(r.body);
}

Map<String, WS> _fromNet(List rows, String coin, String list, String dep, String wd) {
  final m = <String, WS>{};
  for (final e in rows) {
    final l = (e[list] as List?) ?? const [];
    if (l.isEmpty) continue;
    final c = '${e[coin]}'.toUpperCase();
    m[c] = (
      dep: l.any((n) => _b(n[dep])),
      wd:  l.any((n) => _b(n[wd])),
      known: true,
    );
  }
  return m;
}

Future<Map<String, WS>> _signed(String url, String hdr, Map<String, String> k, {bool wrap = false}) async {
  final q = 'timestamp=${_now()}&recvWindow=10000';
  final j = await _j('$url?$q&signature=${_hmac(q, k['secret']!)}', {hdr: k['key']!});
  return _fromNet(wrap ? j['data'] : j, 'coin', 'networkList', 'depositEnable', 'withdrawEnable');
}

typedef WalletFn = Future<Map<String, WS>> Function(Map<String, String> k);

final Map<String, WalletFn> walletApis = {
  'KuCoin': (_) async {
    final j = await _j('https://api.kucoin.com/api/v3/currencies');
    return _fromNet(j['data'], 'currency', 'chains', 'isDepositEnabled', 'isWithdrawEnabled');
  },
  'Gate': (_) async {
    final m = <String, WS>{};
    for (final e in await _j('https://api.gateio.ws/api/v4/spot/currencies') as List) {
      m['${e['currency']}'.toUpperCase()] = (
        dep: !_b(e['deposit_disabled']),
        wd: !_b(e['withdraw_disabled']),
        known: true,
      );
    }
    return m;
  },
  'Bitget': (_) async {
    final j = await _j('https://api.bitget.com/api/v2/spot/public/coins');
    return _fromNet(j['data'], 'coin', 'chains', 'rechargeable', 'withdrawable');
  },
  'Binance': (k) => _signed('https://api.binance.com/sapi/v1/capital/config/getall', 'X-MBX-APIKEY', k),
  'MEXC': (k) => _signed('https://api.mexc.com/api/v3/capital/config/getall', 'X-MEXC-APIKEY', k),
  'BingX': (k) => _signed('https://open-api.bingx.com/openApi/wallets/v1/capital/config/getall', 'X-BX-APIKEY', k, wrap: true),
  'Bybit': (k) async {
    final ts = '${_now()}', rw = '10000';
    final j = await _j('https://api.bybit.com/v5/asset/coin/query-info', {
      'X-BAPI-API-KEY': k['key']!,
      'X-BAPI-TIMESTAMP': ts,
      'X-BAPI-RECV-WINDOW': rw,
      'X-BAPI-SIGN': _hmac('$ts${k['key']}$rw', k['secret']!),
    });
    return _fromNet(j['result']['rows'], 'coin', 'chains', 'chainDeposit', 'chainWithdraw');
  },
  'OKX': (k) async {
    final ts = DateTime.fromMillisecondsSinceEpoch(_now(), isUtc: true).toIso8601String();
    final sign = base64.encode(Hmac(sha256, utf8.encode(k['secret']!))
        .convert(utf8.encode('${ts}GET/api/v5/asset/currencies'))
        .bytes);
    final j = await _j('https://www.okx.com/api/v5/asset/currencies', {
      'OK-ACCESS-KEY': k['key']!,
      'OK-ACCESS-SIGN': sign,
      'OK-ACCESS-TIMESTAMP': ts,
      'OK-ACCESS-PASSPHRASE': k['pass']!,
    });
    final m = <String, WS>{};
    for (final e in j['data']) {
      final c = '${e['ccy']}'.toUpperCase();
      final o = m[c];
      m[c] = (
        dep: (o?.dep ?? false) || _b(e['canDep']),
        wd:  (o?.wd ?? false) || _b(e['canWd']),
        known: true,
      );
    }
    return m;
  },
};