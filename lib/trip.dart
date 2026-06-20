import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';

class TripPoint {
  final double lat;
  final double lng;
  final double speedKmh;
  final int millisFromStart;

  TripPoint({
    required this.lat,
    required this.lng,
    required this.speedKmh,
    required this.millisFromStart,
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        's': speedKmh,
        'm': millisFromStart,
      };

  factory TripPoint.fromJson(Map<String, dynamic> j) => TripPoint(
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        speedKmh: (j['s'] as num).toDouble(),
        millisFromStart: j['m'] as int,
      );
}

class Trip {
  final String id;
  final DateTime startedAt;
  final int durationSec;
  final double distanceKm;
  final double topSpeedKmh;
  final int peakScore;
  final List<TripPoint> points;

  Trip({
    required this.id,
    required this.startedAt,
    required this.durationSec,
    required this.distanceKm,
    required this.topSpeedKmh,
    required this.peakScore,
    required this.points,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'durationSec': durationSec,
        'distanceKm': distanceKm,
        'topSpeedKmh': topSpeedKmh,
        'peakScore': peakScore,
        'points': points.map((p) => p.toJson()).toList(),
      };

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        id: j['id'] as String,
        startedAt: DateTime.parse(j['startedAt'] as String),
        durationSec: j['durationSec'] as int,
        distanceKm: (j['distanceKm'] as num).toDouble(),
        topSpeedKmh: (j['topSpeedKmh'] as num).toDouble(),
        peakScore: j['peakScore'] as int,
        points: (j['points'] as List)
            .map((p) => TripPoint.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}

class TripStore {
  static const _key = 'trips_v1';
  static const _maxTrips = 20;
  static const _minDurationSec = 30;
  static const _minDistanceKm = 0.1;

  static Future<List<Trip>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Trip.fromJson(e as Map<String, dynamic>))
          .toList()
          .reversed
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> save(Trip trip) async {
    if (trip.durationSec < _minDurationSec) return false;
    if (trip.distanceKm < _minDistanceKm) return false;
    if (trip.points.length < 2) return false;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    List<dynamic> list = [];
    if (raw != null) {
      try {
        list = jsonDecode(raw) as List;
      } catch (_) {}
    }
    list.add(trip.toJson());
    if (list.length > _maxTrips) {
      list = list.sublist(list.length - _maxTrips);
    }
    await prefs.setString(_key, jsonEncode(list));
    return true;
  }

  static Future<void> delete(String tripId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      list.removeWhere((e) => (e as Map<String, dynamic>)['id'] == tripId);
      await prefs.setString(_key, jsonEncode(list));
    } catch (_) {}
  }
}

class TripBuilder {
  final String id;
  final DateTime startedAt;
  final List<TripPoint> _points = [];
  double _distanceKm = 0;
  double _topSpeedKmh = 0;
  int _peakScore = 0;
  double? _lastLat;
  double? _lastLng;
  int _lastPointMs = -10000;

  TripBuilder({required this.id, required this.startedAt});

  static const _pointIntervalMs = 2000;

  void addPoint(double lat, double lng, double speedKmh) {
    final nowMs = DateTime.now().difference(startedAt).inMilliseconds;
    if (nowMs - _lastPointMs < _pointIntervalMs) return;
    _lastPointMs = nowMs;

    if (_lastLat != null && _lastLng != null) {
      _distanceKm += _haversineKm(_lastLat!, _lastLng!, lat, lng);
    }
    _lastLat = lat;
    _lastLng = lng;

    if (speedKmh > _topSpeedKmh) _topSpeedKmh = speedKmh;

    _points.add(TripPoint(
      lat: lat,
      lng: lng,
      speedKmh: speedKmh,
      millisFromStart: nowMs,
    ));
  }

  void updateScore(int score) {
    if (score > _peakScore) _peakScore = score;
  }

  Trip build() {
    final duration = DateTime.now().difference(startedAt).inSeconds;
    return Trip(
      id: id,
      startedAt: startedAt,
      durationSec: duration,
      distanceKm: _distanceKm,
      topSpeedKmh: _topSpeedKmh,
      peakScore: _peakScore,
      points: List.unmodifiable(_points),
    );
  }

  bool get hasPoints => _points.isNotEmpty;

  static double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final sinDLat = math.sin(dLat / 2);
    final sinDLng = math.sin(dLng / 2);
    final a = sinDLat * sinDLat +
        math.cos(_toRad(lat1)) * math.cos(_toRad(lat2)) * sinDLng * sinDLng;
    final c = 2 * math.asin(math.sqrt(a));
    return r * c;
  }

  static double _toRad(double deg) => deg * math.pi / 180.0;
}
