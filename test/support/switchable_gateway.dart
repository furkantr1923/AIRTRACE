import 'package:airtrace/src/data/sources/http_gateway.dart';
import 'package:airtrace/src/data/sources/source_errors.dart';

/// Gerçek ağ istemcisini saran, testte "interneti kesip açmayı" sağlayan
/// geçit. [offline] true iken her istek OfflineException fırlatır; false iken
/// istekler gerçek sunuculara gider.
class SwitchableGateway extends HttpGateway {
  SwitchableGateway({this.offline = false});

  bool offline;

  @override
  Future<GatewayResponse> getJson(Uri uri, {Map<String, String>? headers}) {
    if (offline) return Future.error(const OfflineException());
    return super.getJson(uri, headers: headers);
  }

  @override
  Future<GatewayResponse> postJson(Uri uri, Object body, {Map<String, String>? headers}) {
    if (offline) return Future.error(const OfflineException());
    return super.postJson(uri, body, headers: headers);
  }

  @override
  Future<GatewayResponse> postForm(Uri uri, Map<String, String> form) {
    if (offline) return Future.error(const OfflineException());
    return super.postForm(uri, form);
  }
}
