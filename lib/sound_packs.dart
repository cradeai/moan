import 'package:shared_preferences/shared_preferences.dart';

enum PackType { crossfade, rateModulated }

class SoundPack {
  final String id;
  final String name;
  final PackType type;
  final String light;
  final String medium;
  final String intense;
  final String single;

  const SoundPack._({
    required this.id,
    required this.name,
    required this.type,
    this.light = '',
    this.medium = '',
    this.intense = '',
    this.single = '',
  });

  const SoundPack.crossfade({
    required String id,
    required String name,
    required String light,
    required String medium,
    required String intense,
  }) : this._(
          id: id,
          name: name,
          type: PackType.crossfade,
          light: light,
          medium: medium,
          intense: intense,
        );

  const SoundPack.rateModulated({
    required String id,
    required String name,
    required String single,
  }) : this._(
          id: id,
          name: name,
          type: PackType.rateModulated,
          single: single,
        );
}

class SoundPacks {
  static const SoundPack moan = SoundPack.crossfade(
    id: 'moan',
    name: 'Moan',
    light: 'audio/light_loop.mp3',
    medium: 'audio/medium_loop.mp3',
    intense: 'audio/intense_loop.mp3',
  );

  static const SoundPack fart = SoundPack.crossfade(
    id: 'fart',
    name: 'Fart',
    light: 'audio/packs/fart/light.mp3',
    medium: 'audio/packs/fart/medium.mp3',
    intense: 'audio/packs/fart/intense.mp3',
  );

  static const SoundPack engine = SoundPack.rateModulated(
    id: 'engine',
    name: 'Engine',
    single: 'audio/packs/engine/idle.mp3',
  );

  static const List<SoundPack> all = [moan, fart, engine];

  static const _key = 'sound_pack_id';
  static SoundPack _current = moan;

  static SoundPack get current => _current;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_key);
    if (id != null) {
      _current = all.firstWhere((p) => p.id == id, orElse: () => moan);
    }
  }

  static Future<void> setCurrent(SoundPack pack) async {
    _current = pack;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, pack.id);
  }
}
