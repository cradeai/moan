import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class LeaderboardEntry {
  final String deviceId;
  final String displayName;
  final int score;
  final String mode;
  final DateTime createdAt;

  LeaderboardEntry({
    required this.deviceId,
    required this.displayName,
    required this.score,
    required this.mode,
    required this.createdAt,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      deviceId: json['device_id'] as String,
      displayName: json['display_name'] as String,
      score: json['score'] as int,
      mode: json['mode'] as String,
      createdAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class Leaderboard {
  static const _kDeviceId = 'leaderboard_device_id';
  static const _kDisplayName = 'leaderboard_display_name';
  static const _kBestSubmitted = 'leaderboard_best_submitted';
  static const _kLastSubmit = 'leaderboard_last_submit_ms';
  static const _minSubmitIntervalMs = 30000;

  static late SharedPreferences _prefs;
  static late String _deviceId;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    var id = _prefs.getString(_kDeviceId);
    if (id == null) {
      id = const Uuid().v4();
      await _prefs.setString(_kDeviceId, id);
    }
    _deviceId = id;
  }

  static String get deviceId => _deviceId;

  static String? get displayName => _prefs.getString(_kDisplayName);

  static Future<void> setDisplayName(String name) async {
    await _prefs.setString(_kDisplayName, name.trim());
  }

  static bool get hasDisplayName {
    final n = displayName;
    return n != null && n.isNotEmpty;
  }

  static int get bestSubmittedScore => _prefs.getInt(_kBestSubmitted) ?? 0;

  static Future<bool> submitScore({required int score, required String mode}) async {
    if (!hasDisplayName) return false;
    if (score <= bestSubmittedScore) return false;
    if (score < 0 || score > 100) return false;

    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _prefs.getInt(_kLastSubmit) ?? 0;
    if (now - last < _minSubmitIntervalMs) return false;

    try {
      await Supabase.instance.client.from('scores').upsert({
        'device_id': _deviceId,
        'display_name': displayName,
        'score': score,
        'mode': mode,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'device_id');
      await _prefs.setInt(_kBestSubmitted, score);
      await _prefs.setInt(_kLastSubmit, now);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<LeaderboardEntry>> fetchTop({int limit = 100, String? mode}) async {
    try {
      var query = Supabase.instance.client.from('scores').select();
      if (mode != null) {
        query = query.eq('mode', mode);
      }
      final data = await query.order('score', ascending: false).limit(limit);
      return (data as List)
          .map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
