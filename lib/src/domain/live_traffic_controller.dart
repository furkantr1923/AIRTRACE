import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/aircraft.dart';
import '../data/sources/adsblol_source.dart';
import '../data/sources/opensky_source.dart';
import '../data/sources/source_errors.dart';
import 'fetch_planner.dart';
import 'traffic_store.dart';

enum LinkStatus {
  /// İlk veri bekleniyor.
  connecting,

  /// Son 30 sn içinde başarılı veri alındı.
  live,

  /// Bağlantı var ama veriler eski (sağlayıcı hatası/limit).
  stale,

  /// İnternet veya sağlayıcılara erişim yok.
  offline,
}

/// Canlı veri döngüsü.
///
/// Tek bir 1 sn'lik zamanlayıcı her kaynağın "sıradaki istek zamanını"
/// kontrol eder; böylece istekler asla üst üste binmez ve limitler tek
/// yerden yönetilir. Uygulama arka plandayken döngü tamamen durur.
class LiveTrafficController extends ChangeNotifier {
  LiveTrafficController({
    required this.store,
    required this.adsb,
    required this.openSky,
    this.planner = const FetchPlanner(),
    this.budget = const OpenSkyBudget(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Varsayılan yenileme aralığı (istenen değer: 10 sn).
  static const adsbInterval = Duration(seconds: 10);
  static const _liveWindow = Duration(seconds: 30);

  final TrafficStore store;
  final AdsbLolSource adsb;
  final OpenSkySource openSky;
  final FetchPlanner planner;
  final OpenSkyBudget budget;
  final DateTime Function() _clock;

  Timer? _timer;
  MapViewport? _viewport;
  bool _running = false;

  DateTime _adsbDue = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _openSkyDue = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _followDue = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPrune = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastAdsbRequest;
  bool _adsbBusy = false, _openSkyBusy = false, _followBusy = false;
  int _adsbFailures = 0, _openSkyFailures = 0;
  DateTime? _openSkyBlockedUntil;

  /// Seçili uçak görüş alanı dışında kalırsa tek uçak sorgusuyla takip edilir.
  String? followHex;

  DateTime? lastSuccess;
  DateTime? lastAdsbSuccess;
  DateTime? lastOpenSkySuccess;
  String? lastError;
  bool _lastErrorOffline = false;
  Duration openSkyInterval = const Duration(seconds: 60);

  /// Son planın ADS-B.lol / OpenSky kullanıp kullanmadığı (durum çubuğu için).
  bool usingAdsb = false, usingOpenSky = false;

  bool get isRunning => _running;
  MapViewport? get viewport => _viewport;
  /// Son engel nedeni kota mı (true) yoksa sağlayıcı hatası mı (false).
  bool openSkyQuotaExhausted = false;

  bool get openSkyBlocked => _openSkyBlockedUntil != null && _clock().isBefore(_openSkyBlockedUntil!);
  DateTime? get openSkyBlockedUntil => openSkyBlocked ? _openSkyBlockedUntil : null;

  LinkStatus get status {
    final now = _clock();
    if (lastSuccess != null && now.difference(lastSuccess!) <= _liveWindow) return LinkStatus.live;
    if (lastError == null) return lastSuccess == null ? LinkStatus.connecting : LinkStatus.stale;
    return _lastErrorOffline ? LinkStatus.offline : LinkStatus.stale;
  }

  void start() {
    if (_running) return;
    _running = true;
    _adsbDue = _openSkyDue = _clock();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    tick();
    notifyListeners();
  }

  /// Arka plana geçince çağrılır: hiçbir istek gönderilmez.
  void pause() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void setViewport(MapViewport v) {
    final old = _viewport;
    _viewport = v;
    if (old != null && old.similarTo(v)) return;
    // Görünüm değişince ADS-B.lol'u kısa bir gecikmeyle (pan/zoom bitsin diye)
    // yenile; ancak iki istek arası en az 3 sn kuralını bozma.
    final now = _clock();
    var due = now.add(const Duration(milliseconds: 700));
    if (_lastAdsbRequest != null) {
      final earliest = _lastAdsbRequest!.add(const Duration(seconds: 3));
      if (earliest.isAfter(due)) due = earliest;
    }
    if (due.isBefore(_adsbDue)) _adsbDue = due;
    // OpenSky için bütçe korunur: yalnızca daha önce hiç istek atılmadıysa
    // hemen gönderilir.
    if (lastOpenSkySuccess == null && !openSkyBlocked && due.isBefore(_openSkyDue)) _openSkyDue = due;
  }

  /// Bağlantı geri geldiğinde veya kullanıcı yenile dediğinde.
  void retryNow() {
    final now = _clock();
    _adsbDue = now;
    if (!openSkyBlocked && lastOpenSkySuccess == null) _openSkyDue = now;
    tick();
  }

  @visibleForTesting
  Future<void> tick() async {
    if (!_running) return;
    final v = _viewport;
    final now = _clock();
    if (now.difference(_lastPrune) > const Duration(seconds: 5)) {
      _lastPrune = now;
      store.prune(online: status == LinkStatus.live, now: now, keepHex: followHex);
    }
    if (v == null) return;
    final plan = planner.plan(v, openSkyAvailable: !openSkyBlocked);
    usingAdsb = plan.useAdsbLol;
    usingOpenSky = plan.useOpenSky;

    final jobs = <Future<void>>[];
    if (plan.useAdsbLol && !_adsbBusy && !now.isBefore(_adsbDue)) {
      jobs.add(_runAdsb(plan));
    }
    if (plan.useOpenSky && !_openSkyBusy && !now.isBefore(_openSkyDue)) {
      jobs.add(_runOpenSky(plan));
    }
    if (followHex != null && !_followBusy && !now.isBefore(_followDue)) {
      final t = store[followHex!];
      final fresh = t != null && now.difference(t.receivedAt) < const Duration(seconds: 15);
      if (!fresh) jobs.add(_runFollow(followHex!));
    }
    if (jobs.isNotEmpty) await Future.wait(jobs);
  }

  Future<void> _runAdsb(FetchPlan plan) async {
    _adsbBusy = true;
    _lastAdsbRequest = _clock();
    try {
      final list = await adsb.fetchCircle(plan.circleCenter!, plan.circleRadiusNm!);
      _onSuccess(list, adsbInterval);
      lastAdsbSuccess = _clock();
      _adsbFailures = 0;
      _adsbDue = _clock().add(adsbInterval);
    } on SourceException catch (e) {
      _adsbFailures++;
      _adsbDue = _clock().add(_backoff(e, _adsbFailures));
      _onError(e);
    } finally {
      _adsbBusy = false;
    }
  }

  Future<void> _runOpenSky(FetchPlan plan) async {
    _openSkyBusy = true;
    final cost = OpenSkySource.creditCost(plan.openSkyBox);
    try {
      final list = await openSky.fetchStates(plan.openSkyBox);
      openSkyInterval = budget.interval(
        cost: cost,
        remaining: openSky.remainingCredits,
        daily: openSky.dailyCredits,
        authenticated: openSky.isAuthenticated,
      );
      _onSuccess(list, openSkyInterval);
      lastOpenSkySuccess = _clock();
      _openSkyFailures = 0;
      openSkyQuotaExhausted = false;
      _openSkyDue = _clock().add(openSkyInterval);
    } on RateLimitedException catch (e) {
      _openSkyFailures++;
      _openSkyBlockedUntil = _clock().add(e.retryAfter);
      _openSkyDue = _openSkyBlockedUntil!;
      openSkyQuotaExhausted = true;
      _adsbDue = _clock();
      notifyListeners();
    } on OfflineException catch (e) {
      _openSkyFailures++;
      _openSkyDue = _clock().add(_backoff(e, _openSkyFailures, base: 10));
      _onError(e);
    } on SourceException {
      // Sağlayıcı reddetti / hata verdi: geniş alan geçici olarak devre dışı,
      // harita merkezi ADS-B.lol ile canlı tutulur (FetchPlanner geri düşer).
      _openSkyFailures++;
      final wait = Duration(seconds: (60 * (1 << (_openSkyFailures - 1).clamp(0, 3))).clamp(60, 600));
      _openSkyBlockedUntil = _clock().add(wait);
      _openSkyDue = _openSkyBlockedUntil!;
      _adsbDue = _clock();
      notifyListeners();
    } finally {
      _openSkyBusy = false;
    }
  }

  Future<void> _runFollow(String hex) async {
    _followBusy = true;
    try {
      final list = await adsb.fetchByHex(hex);
      if (list.isNotEmpty) _onSuccess(list, adsbInterval);
    } on SourceException {
      // Takip isteğe bağlıdır; ana durum mesajını etkilemez.
    } finally {
      _followDue = _clock().add(adsbInterval);
      _followBusy = false;
    }
  }

  void _onSuccess(List<Aircraft> list, Duration refresh) {
    store.ingest(list, expectedRefresh: refresh, now: _clock());
    lastSuccess = _clock();
    lastError = null;
    _lastErrorOffline = false;
    notifyListeners();
  }

  void _onError(SourceException e) {
    lastError = e.message;
    _lastErrorOffline = e is OfflineException;
    notifyListeners();
  }

  Duration _backoff(SourceException e, int failures, {int base = 5}) {
    if (e is RateLimitedException) return e.retryAfter;
    final s = base * (1 << (failures - 1).clamp(0, 3));
    return Duration(seconds: s.clamp(base, 60));
  }

  /// Kullanıcının açık aramasıyla tek seferlik ağ sorgusu (uçuş kodu,
  /// tescil veya hex). Yerel veride bulunamayan uçaklar için.
  Future<List<Aircraft>> searchRemote(String query) async {
    final q = query.trim();
    final results = <Aircraft>[];
    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(q)) {
      results.addAll(await adsb.fetchByHex(q));
    }
    if (results.isEmpty && RegExp(r'^[A-Za-z0-9-]{3,8}$').hasMatch(q)) {
      results.addAll(q.contains('-') ? await adsb.fetchByRegistration(q) : await adsb.fetchByCallsign(q));
      if (results.isEmpty && !q.contains('-')) results.addAll(await adsb.fetchByRegistration(q));
    }
    if (results.isNotEmpty) _onSuccess(results, adsbInterval);
    return results;
  }
}
