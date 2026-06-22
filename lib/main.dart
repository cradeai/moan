import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'leaderboard.dart';
import 'leaderboard_page.dart';
import 'onboarding_page.dart';
import 'safety_dialog.dart';
import 'sound_packs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://pimbnbqmdnyhzjndwhmr.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBpbWJuYnFtZG55aHpqbmR3aG1yIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUxMjEwODEsImV4cCI6MjA5MDY5NzA4MX0.Gjr0JCa9EjqyctFSs1mH2SCXtnGJZCEglduxAZI35QY',
  );
  await Leaderboard.init();
  await SoundPacks.init();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const MoanApp());
}

class MoanApp extends StatelessWidget {
  const MoanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vroomy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      home: const RootGate(),
    );
  }
}

class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool? _onboardingDone;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final done = await OnboardingPage.hasCompleted();
    if (mounted) setState(() => _onboardingDone = done);
  }

  @override
  Widget build(BuildContext context) {
    if (_onboardingDone == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.purple)),
      );
    }
    if (!_onboardingDone!) {
      return OnboardingPage(onComplete: () => setState(() => _onboardingDone = true));
    }
    return const MoanPage();
  }
}

class MoanPage extends StatefulWidget {
  const MoanPage({super.key});

  @override
  State<MoanPage> createState() => _MoanPageState();
}

class _MoanPageState extends State<MoanPage> {
  StreamSubscription? _subscription;
  StreamSubscription<Position>? _positionSub;
  Timer? _decayTimer;
  final AudioPlayer _lightPlayer = AudioPlayer();
  final AudioPlayer _mediumPlayer = AudioPlayer();
  final AudioPlayer _intensePlayer = AudioPlayer();
  bool _playersStarted = false;

  bool _enabled = true;
  bool _carMode = true;
  int _gpsUpdates = 0;
  String _gpsDebug = '';
  double _currentForce = 0;
  double _currentSpeed = 0; // km/h
  final bool _isIpad = Platform.isIOS && WidgetsBinding.instance.platformDispatcher.views.first.physicalSize.shortestSide / WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio > 600;
  double get _sensitivity => _isIpad ? 4.5 : 8.0;
  bool _flash = false;

  // Score system
  double _score = 0;
  double _maxScore = 0;
  double _accelBoost = 0; // drive mode: extra score above speed baseline
  static const double _maxScoreLimit = 100.0;
  static const double _decayRate = 8.0; // points per second decay (shake)
  static const double _accelBoostDecay = 4.0; // boost decay per second (drive)
  static const int _shakeCooldownMs = 200;
  DateTime _lastShakeTime = DateTime.fromMillisecondsSinceEpoch(0);

  double _speedBase(double kmh) => (kmh * 0.7).clamp(0.0, 80.0);

  final List<LatLng> _liveRoute = [];
  LatLng? _liveCenter;
  final MapController _mapController = MapController();
  double _smoothedHeading = 0;
  bool _hasHeading = false;
  static const double _rotationMinSpeedKmh = 8.0;



  @override
  void initState() {
    super.initState();
    _startLoop();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initPrimaryMode());
    _decayTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_carMode) {
        if (_accelBoost > 0) {
          setState(() {
            _accelBoost = (_accelBoost - _accelBoostDecay * 0.05).clamp(0.0, 100.0);
            _score = (_speedBase(_currentSpeed) + _accelBoost).clamp(0.0, _maxScoreLimit);
          });
        }
      } else {
        if (_score > 0) {
          setState(() {
            _score = (_score - _decayRate * 0.05).clamp(0.0, _maxScoreLimit);
          });
        }
      }
    });
  }

  Future<void> _initPrimaryMode() async {
    final ok = await _enableDriveMode(showErrors: false);
    if (!ok) await _enableShakeMode();
  }


  Future<void> _openLeaderboard() async {
    if (!Leaderboard.hasDisplayName) {
      final name = await showDisplayNameDialog(context);
      if (name == null || name.isEmpty) return;
      await Leaderboard.setDisplayName(name);
      if (_maxScore > 0) {
        await Leaderboard.submitScore(
          score: _maxScore.toInt(),
          mode: _carMode ? 'drive' : 'shake',
        );
      }
    }
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LeaderboardPage()),
      );
    }
  }

  Timer? _audioTimer;

  double _lastLightVol = -1;
  double _lastMediumVol = -1;
  double _lastIntenseVol = -1;
  double _lastRate = -1;
  double _smoothedRateTarget = 1.0;

  Future<void> _reloadSoundPack() async {
    await _lightPlayer.stop();
    await _mediumPlayer.stop();
    await _intensePlayer.stop();
    _lastLightVol = -1;
    _lastMediumVol = -1;
    _lastIntenseVol = -1;
    _lastRate = -1;
    _smoothedRateTarget = 1.0;
    await _lightPlayer.setPlaybackRate(1.0);
    final pack = SoundPacks.current;
    if (pack.type == PackType.crossfade) {
      await _lightPlayer.play(AssetSource(pack.light), volume: 0);
      await _mediumPlayer.play(AssetSource(pack.medium), volume: 0);
      await _intensePlayer.play(AssetSource(pack.intense), volume: 0);
    } else {
      await _lightPlayer.play(AssetSource(pack.single), volume: 0);
    }
  }

  Future<void> _startLoop() async {
    print('[AUDIO] _startLoop begin');
    try {
      await AudioPlayer.global.setAudioContext(AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
        android: AudioContextAndroid(
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
        ),
      ));
      print('[AUDIO] context set');

      await _lightPlayer.setReleaseMode(ReleaseMode.loop);
      await _mediumPlayer.setReleaseMode(ReleaseMode.loop);
      await _intensePlayer.setReleaseMode(ReleaseMode.loop);
      print('[AUDIO] release modes set');

      final pack = SoundPacks.current;
      if (pack.type == PackType.crossfade) {
        await _lightPlayer.play(AssetSource(pack.light), volume: 0);
        print('[AUDIO] light playing (${pack.id})');
        await _mediumPlayer.play(AssetSource(pack.medium), volume: 0);
        print('[AUDIO] medium playing (${pack.id})');
        await _intensePlayer.play(AssetSource(pack.intense), volume: 0);
        print('[AUDIO] intense playing (${pack.id})');
      } else {
        await _lightPlayer.play(AssetSource(pack.single), volume: 0);
        print('[AUDIO] single playing (${pack.id})');
      }

      _playersStarted = true;
      print('[AUDIO] all 3 loops started');
    } catch (e, st) {
      print('[AUDIO ERROR] $e\n$st');
    }

    // Continuous crossfade based on score (100ms = 10x/sec, smooth enough)
    _audioTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _updateCrossfade();
    });
  }

  void _updateCrossfade() {
    final score = _score;

    // Rate-modulated packs (e.g. Engine): single file, vary rate + volume.
    // Drive mode only — engine doesn't make sense without a car.
    if (SoundPacks.current.type == PackType.rateModulated) {
      final normalized = (score / 100).clamp(0.0, 1.0);
      final targetRate = 0.9 + normalized * 0.5; // narrow range: 0.9 -> 1.4
      _smoothedRateTarget = _smoothedRateTarget * 0.85 + targetRate * 0.15;
      final targetVol = (!_carMode || score <= 0) ? 0.0 : (0.15 + normalized * 0.85).clamp(0.0, 1.0);
      final isSilent = targetVol == 0.0;
      if (isSilent || (targetVol - _lastLightVol).abs() > 0.02) {
        _lightPlayer.setVolume(targetVol).catchError((e) => print('[VOL ERR engine] $e'));
        _lastLightVol = targetVol;
      }
      if (_carMode && (_smoothedRateTarget - _lastRate).abs() > 0.05) {
        _lightPlayer.setPlaybackRate(_smoothedRateTarget).catchError((e) => print('[RATE ERR engine] $e'));
        _lastRate = _smoothedRateTarget;
      }
      return;
    }

    // Compute volume for each band with overlapping triangular fades
    // Light:   peaks at score 15, fades out by 50
    // Medium:  peaks at score 50, 0 outside 15-85
    // Intense: peaks at score 85, fades in from 50
    double lightVol = 0;
    double mediumVol = 0;
    double intenseVol = 0;

    if (score > 0) {
      // Light band (0-50)
      if (score <= 15) {
        lightVol = score / 15; // rising 0→1
      } else if (score <= 50) {
        lightVol = 1 - (score - 15) / 35; // falling 1→0
      }
      // Medium band (15-85)
      if (score > 15 && score <= 50) {
        mediumVol = (score - 15) / 35; // rising 0→1
      } else if (score > 50 && score < 85) {
        mediumVol = 1 - (score - 50) / 35; // falling 1→0
      }
      // Intense band (50-100)
      if (score > 50 && score <= 85) {
        intenseVol = (score - 50) / 35; // rising 0→1
      } else if (score > 85) {
        intenseVol = 1;
      }
    }

    // Master volume scales quadratically for bigger contrast low vs high
    final normalized = (score / 100).clamp(0.0, 1.0);
    final master = score <= 0 ? 0.0 : (0.05 + normalized * normalized * 0.95).clamp(0.0, 1.0);
    lightVol *= master;
    mediumVol *= master;
    intenseVol *= master;

    // Only update volume if changed meaningfully (reduces audio session churn).
    // Always force-update when target is exactly 0 so sound fully stops.
    final isSilent = score <= 0;
    if (isSilent || (lightVol - _lastLightVol).abs() > 0.02) {
      _lightPlayer.setVolume(lightVol).catchError((e) => print('[VOL ERR light] $e'));
      _lastLightVol = lightVol;
    }
    if (isSilent || (mediumVol - _lastMediumVol).abs() > 0.02) {
      _mediumPlayer.setVolume(mediumVol).catchError((e) => print('[VOL ERR medium] $e'));
      _lastMediumVol = mediumVol;
    }
    if (isSilent || (intenseVol - _lastIntenseVol).abs() > 0.02) {
      _intensePlayer.setVolume(intenseVol).catchError((e) => print('[VOL ERR intense] $e'));
      _lastIntenseVol = intenseVol;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _positionSub?.cancel();
    _decayTimer?.cancel();
    _audioTimer?.cancel();
    _lightPlayer.dispose();
    _mediumPlayer.dispose();
    _intensePlayer.dispose();
    super.dispose();
  }

  void _startListening() {
    _subscription?.cancel();
    _subscription = userAccelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 50),
    ).listen(_onMotion);
  }

  Future<bool> _enableDriveMode({bool showErrors = true}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (showErrors && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Turn on Location Services'), backgroundColor: Colors.red),
        );
      }
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    final granted = permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
    if (!granted) {
      if (showErrors && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission required'), backgroundColor: Colors.red),
        );
      }
      return false;
    }

    _subscription?.cancel();
    _lastPosition = null;
    _lastSpeedForAccel = 0;
    _lastAccelTime = DateTime.now();

    _positionSub = Geolocator.getPositionStream(
      locationSettings: AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        activityType: ActivityType.automotiveNavigation,
        allowBackgroundLocationUpdates: false,
      ),
    ).listen(
      _onPosition,
      onError: (e) {
        if (!mounted) return;
        _enableShakeMode();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location unavailable, switched to Shake Mode'),
            backgroundColor: Colors.orange,
          ),
        );
      },
    );

    _minSpeedSinceLastTrigger = 0;
    _liveRoute.clear();
    _liveCenter = null;

    if (mounted) {
      setState(() {
        _carMode = true;
        _gpsUpdates = 0;
      });
    }
    return true;
  }

  Future<void> _enableShakeMode() async {
    _positionSub?.cancel();
    _lastPosition = null;
    _currentSpeed = 0;
    _score = 0;
    _accelBoost = 0;
    _startListening();
    // Engine pack doesn't work in shake mode — switch to Moan.
    if (SoundPacks.current.type == PackType.rateModulated) {
      await SoundPacks.setCurrent(SoundPacks.moan);
      await _reloadSoundPack();
    }
    if (mounted) setState(() => _carMode = false);
  }

  Future<void> _toggleCarMode() async {
    if (!_carMode) {
      await _enableDriveMode();
    } else {
      await _enableShakeMode();
    }
  }

  Position? _lastPosition;
  double _minSpeedSinceLastTrigger = 0;
  DateTime _minSpeedTime = DateTime.now();
  double _lastSpeedForAccel = 0;
  DateTime _lastAccelTime = DateTime.now();
  static const double _speedJumpThreshold = 20.0; // km/h
  static const int _jumpWindowMs = 3000; // must happen within 3 sec

  void _onPosition(Position position) {
    double speedKmh = 0;
    _gpsUpdates++;

    if (position.speed > 0.5) {
      speedKmh = position.speed * 3.6;
    } else if (_lastPosition != null) {
      final dist = Geolocator.distanceBetween(
        _lastPosition!.latitude, _lastPosition!.longitude,
        position.latitude, position.longitude,
      );
      final timeSec = position.timestamp.difference(_lastPosition!.timestamp).inMilliseconds / 1000.0;

      if (timeSec > 0.3 && timeSec < 10) {
        final calculated = (dist / timeSec) * 3.6;
        if (calculated < _currentSpeed + 30 || _currentSpeed == 0) {
          speedKmh = calculated;
        } else {
          speedKmh = _currentSpeed;
        }
      }
    }

    _lastPosition = position;
    speedKmh = speedKmh.clamp(0.0, 300.0);
    final smoothed = _currentSpeed * 0.3 + speedKmh * 0.7;

    // Track the lowest speed since last trigger
    if (smoothed < _minSpeedSinceLastTrigger) {
      _minSpeedSinceLastTrigger = smoothed;
      _minSpeedTime = DateTime.now();
    }

    // Reset min if window expired (slow acceleration doesn't count)
    if (DateTime.now().difference(_minSpeedTime).inMilliseconds > _jumpWindowMs) {
      _minSpeedSinceLastTrigger = smoothed;
      _minSpeedTime = DateTime.now();
    }

    // Check for 20 km/h jump within 3 sec window
    final jump = smoothed - _minSpeedSinceLastTrigger;
    if (jump >= _speedJumpThreshold) {
      _minSpeedSinceLastTrigger = smoothed;
      _minSpeedTime = DateTime.now();
    }

    // Compute acceleration (km/h per second) and add to score
    final now = DateTime.now();
    final dt = now.difference(_lastAccelTime).inMilliseconds / 1000.0;
    double accel = 0;
    if (dt > 0.2) {
      if (dt < 5) {
        accel = (smoothed - _lastSpeedForAccel) / dt;
      }
      // Always reset baseline so a long GPS gap doesn't permanently break accel calc.
      _lastSpeedForAccel = smoothed;
      _lastAccelTime = now;
    }

    final newPoint = LatLng(position.latitude, position.longitude);
    final shouldAddToRoute = _liveRoute.isEmpty ||
        const Distance().as(LengthUnit.Meter, _liveRoute.last, newPoint) > 5;
    if (shouldAddToRoute) {
      _liveRoute.add(newPoint);
      if (_liveRoute.length > 500) _liveRoute.removeAt(0);
    }
    _liveCenter = newPoint;

    // Smooth heading + only rotate when moving fast enough.
    if (smoothed >= _rotationMinSpeedKmh && position.heading >= 0) {
      final h = position.heading;
      if (!_hasHeading) {
        _smoothedHeading = h;
        _hasHeading = true;
      } else {
        // Shortest angular distance interpolation.
        var delta = h - _smoothedHeading;
        if (delta > 180) delta -= 360;
        if (delta < -180) delta += 360;
        _smoothedHeading = (_smoothedHeading + delta * 0.35) % 360;
        if (_smoothedHeading < 0) _smoothedHeading += 360;
      }
    }

    try {
      _mapController.move(newPoint, _mapController.camera.zoom);
      if (_hasHeading) {
        _mapController.rotate(-_smoothedHeading);
      }
    } catch (_) {}

    double points = 0;
    setState(() {
      _currentSpeed = smoothed;
      _currentForce = smoothed;
      if (accel > 1.0) {
        points = (accel - 1.0) * (accel - 1.0) * 2.0;
        _accelBoost = (_accelBoost + points).clamp(0.0, 40.0);
        _flash = accel > 3.0;
      }
      _score = (_speedBase(smoothed) + _accelBoost).clamp(0.0, _maxScoreLimit);
      if (_score > _maxScore) {
        _maxScore = _score;
        Leaderboard.submitScore(score: _maxScore.toInt(), mode: 'drive');
      }
      _gpsDebug = 'GPS #$_gpsUpdates | ${speedKmh.toStringAsFixed(0)} km/h | accel: ${accel.toStringAsFixed(1)}';
    });

    if (accel > 3) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _flash = false);
      });
    }
  }

  void _onMotion(UserAccelerometerEvent event) {
    if (_carMode) return;
    final impact = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    setState(() => _currentForce = impact);

    if (!_enabled) return;

    if (impact > _sensitivity) {
      final now = DateTime.now();
      if (now.difference(_lastShakeTime).inMilliseconds < _shakeCooldownMs) return;
      _lastShakeTime = now;

      final scoreFraction = _score / _maxScoreLimit;
      final difficulty = (1.0 - scoreFraction * scoreFraction).clamp(0.4, 1.0);
      final points = (impact / 10.0).clamp(0.5, 5.0) * difficulty;

      setState(() {
        _score = (_score + points).clamp(0.0, _maxScoreLimit);
        if (_score > _maxScore) {
          _maxScore = _score;
          Leaderboard.submitScore(score: _maxScore.toInt(), mode: 'shake');
        }
        _flash = true;
      });

      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _flash = false);
      });
    }
  }


  String _scoreLabel() {
    if (_score < 10) return '';
    if (_score < 25) return '🔥';
    if (_score < 50) return '🔥🔥';
    if (_score < 75) return '🔥🔥🔥';
    if (_score < 90) return '💀💀💀';
    return '🔥💨💨💨';
  }

  Color _scoreColor() {
    if (_score < 25) return Colors.purple;
    if (_score < 50) return Colors.pink;
    if (_score < 75) return Colors.red;
    return Colors.red.shade200;
  }

  Widget _buildFullScreenMap() {
    if (_liveCenter == null) {
      return Container(
        color: Colors.grey.shade900,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.gps_not_fixed, color: Colors.white38, size: 48),
              SizedBox(height: 12),
              Text('Waiting for GPS...', style: TextStyle(color: Colors.white54, fontSize: 16)),
            ],
          ),
        ),
      );
    }
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _liveCenter!,
            initialZoom: 17,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.moan.moan',
            ),
          ],
        ),
        // Fixed arrow marker centered on screen.
        IgnorePointer(
          child: Center(
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.purpleAccent,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(color: Colors.purpleAccent.withValues(alpha: 0.5), blurRadius: 14),
                ],
              ),
              child: const Icon(Icons.navigation, color: Colors.white, size: 24),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scorePct = (_score / _maxScoreLimit).clamp(0.0, 1.0);

    return Scaffold(
      body: Stack(
        children: [
          if (_carMode)
            Positioned.fill(child: _buildFullScreenMap())
          else
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                color: _flash ? _scoreColor().withValues(alpha: 0.3) : Colors.black,
              ),
            ),
          if (_carMode)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.65),
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.6),
                        Colors.black,
                      ],
                      stops: const [0.0, 0.12, 0.45, 0.72, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          if (_carMode && _flash)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  color: _scoreColor().withValues(alpha: 0.2),
                ),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Text(
                        'Vroomy',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Positioned(
                        left: 8,
                        child: IconButton(
                          icon: Icon(Icons.settings, color: Colors.white.withValues(alpha: 0.85), size: 24),
                          onPressed: () async {
                            final initialPackId = SoundPacks.current.id;
                            await Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => SettingsPage(carMode: _carMode)),
                            );
                            if (SoundPacks.current.id != initialPackId) {
                              await _reloadSoundPack();
                            }
                          },
                        ),
                      ),
                      Positioned(
                        right: 8,
                        child: IconButton(
                          icon: Icon(Icons.emoji_events, color: Colors.white.withValues(alpha: 0.85), size: 24),
                          onPressed: _openLeaderboard,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Score bar (now near bottom, just above force circle)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _score.toInt().toString(),
                            style: TextStyle(
                              fontSize: _carMode ? 38 : 56,
                              fontWeight: FontWeight.w800,
                              color: _scoreColor(),
                            ),
                          ),
                          SizedBox(width: _carMode ? 6 : 8),
                          Text(_scoreLabel(), style: TextStyle(fontSize: _carMode ? 20 : 28)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          height: 16,
                          child: Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              AnimatedFractionallySizedBox(
                                duration: const Duration(milliseconds: 80),
                                widthFactor: scorePct,
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Colors.purple, _scoreColor()],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('0', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5))),
                          Text('Best: ${_maxScore.toInt()}', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5))),
                          Text('100', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5))),
                        ],
                      ),
                    ],
                  ),
                ),

                SizedBox(height: _carMode ? 10 : 16),

                Container(
                  width: _carMode ? 120 : 200,
                  height: _carMode ? 120 : 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Color.lerp(Colors.white, _scoreColor(), scorePct)!,
                      width: 2 + scorePct * (_carMode ? 2 : 3),
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                            _carMode ? _currentSpeed.toInt().toString() : _currentForce.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: _carMode ? 32 : 56,
                              fontWeight: FontWeight.w200,
                              color: Color.lerp(Colors.white, _scoreColor(), scorePct),
                            )),
                        Text(
                          _carMode ? 'km/h' : 'm/s²',
                          style: TextStyle(fontSize: _carMode ? 12 : 18, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: _carMode ? 10 : 16),

                GestureDetector(
                  onTap: () {
                    _toggleCarMode();
                    HapticFeedback.mediumImpact();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: _carMode ? Colors.purple.shade800 : Colors.orange.shade800,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_carMode ? Icons.vibration : Icons.directions_car, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _carMode ? 'Switch to Shake Mode' : 'Switch to Drive Mode',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final bool carMode;
  const SettingsPage({super.key, this.carMode = true});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<void> _changeName() async {
    final name = await showDisplayNameDialog(context);
    if (name == null || name.isEmpty) return;
    await Leaderboard.setDisplayName(name);
    if (mounted) setState(() {});
  }

  Future<void> _selectSoundPack(SoundPack pack) async {
    await SoundPacks.setCurrent(pack);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final name = Leaderboard.displayName;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Leaderboard name', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14)),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    name ?? 'Not set',
                    style: TextStyle(
                      color: name == null ? Colors.white38 : Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _changeName,
                  child: const Text('Change', style: TextStyle(color: Colors.purpleAccent)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Sound Pack', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14)),
            const SizedBox(height: 8),
            ...SoundPacks.all.where((p) => widget.carMode || p.type != PackType.rateModulated).map((pack) {
              final selected = SoundPacks.current.id == pack.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () => _selectSoundPack(pack),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: selected ? Colors.purple.withValues(alpha: 0.2) : Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? Colors.purpleAccent : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: selected ? Colors.purpleAccent : Colors.white38,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          pack.name,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
            _settingsButton(
              context,
              icon: Icons.emoji_events,
              label: 'Leaderboard',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LeaderboardPage()),
              ),
            ),
            const SizedBox(height: 12),
            _settingsButton(
              context,
              icon: Icons.shield_outlined,
              label: 'Drive Safety',
              onTap: () => showSafetyDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsButton(BuildContext context, {required IconData icon, required String label, required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey.shade900,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
