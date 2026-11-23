import 'package:flutter/foundation.dart';

/// Verinin geldiği sağlayıcı.
enum DataSource {
  adsbLol('ADS-B.lol'),
  openSky('OpenSky Network');

  const DataSource(this.label);
  final String label;
}

/// Bir uçağın sağlayıcıdan gelen **gerçek** (tahmin içermeyen) anlık durumu.
///
/// Birimler SI'dır: metre, metre/saniye, derece. Bilinmeyen alanlar `null`
/// kalır; arayüz bunları "Bilinmiyor" olarak gösterir, asla uydurmaz.
@immutable
class Aircraft {
  const Aircraft({
    required this.hex,
    required this.lat,
    required this.lon,
    required this.positionTime,
    required this.source,
    this.callsign,
    this.registration,
    this.typeCode,
    this.originCountry,
    this.altitudeM,
    this.onGround = false,
    this.groundSpeedMs,
    this.trackDeg,
    this.verticalRateMs,
    this.squawk,
  });

  /// ICAO 24-bit adres (küçük harf, 6 hane). Birincil anahtar.
  final String hex;
  final String? callsign;
  final String? registration;
  final String? typeCode;

  /// Sağlayıcının bildirdiği ülke (OpenSky). ADS-B.lol için ICAO bloğundan
  /// türetilir.
  final String? originCountry;

  final double lat;
  final double lon;

  /// Konumun ölçüldüğü an (UTC). Ara değerleme bu andan itibaren yapılır.
  final DateTime positionTime;

  /// Barometrik irtifa (m). Yerdeyse `onGround` true olur.
  final double? altitudeM;
  final bool onGround;
  final double? groundSpeedMs;

  /// Gerçek rota (kuzeyden saat yönünde derece).
  final double? trackDeg;
  final double? verticalRateMs;
  final String? squawk;
  final DataSource source;

  /// Uçuş kodu yoksa kayıt veya hex gösterilir.
  String get displayName =>
      (callsign != null && callsign!.isNotEmpty) ? callsign! : (registration ?? hex.toUpperCase());

  /// ICAO havayolu öneki (ör. THY1234 -> THY). Yalnızca "3 harf + rakam"
  /// biçimindeki uçuş kodlarında anlamlıdır.
  String? get airlineIcao {
    final cs = callsign;
    if (cs == null || cs.length < 4) return null;
    final prefix = cs.substring(0, 3);
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(prefix)) return null;
    if (!RegExp(r'^[0-9]').hasMatch(cs.substring(3))) return null;
    return prefix;
  }

  Aircraft copyWith({String? originCountry}) => Aircraft(
        hex: hex,
        lat: lat,
        lon: lon,
        positionTime: positionTime,
        source: source,
        callsign: callsign,
        registration: registration,
        typeCode: typeCode,
        originCountry: originCountry ?? this.originCountry,
        altitudeM: altitudeM,
        onGround: onGround,
        groundSpeedMs: groundSpeedMs,
        trackDeg: trackDeg,
        verticalRateMs: verticalRateMs,
        squawk: squawk,
      );

  /// İki kayıt birleştirilirken eksik kimlik bilgileri diğerinden tamamlanır
  /// (ör. OpenSky kayıt/tip vermez, ADS-B.lol verir). Konum her zaman daha
  /// yeni olandan alınır.
  Aircraft mergeIdentity(Aircraft older) => Aircraft(
        hex: hex,
        lat: lat,
        lon: lon,
        positionTime: positionTime,
        source: source,
        callsign: callsign ?? older.callsign,
        registration: registration ?? older.registration,
        typeCode: typeCode ?? older.typeCode,
        originCountry: originCountry ?? older.originCountry,
        altitudeM: altitudeM ?? (onGround ? null : older.altitudeM),
        onGround: onGround,
        groundSpeedMs: groundSpeedMs ?? older.groundSpeedMs,
        trackDeg: trackDeg ?? older.trackDeg,
        verticalRateMs: verticalRateMs,
        squawk: squawk ?? older.squawk,
      );
}
