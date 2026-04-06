import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://pimbnbqmdnyhzjndwhmr.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBpbWJuYnFtZG55aHpqbmR3aG1yIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUxMjEwODEsImV4cCI6MjA5MDY5NzA4MX0.Gjr0JCa9EjqyctFSs1mH2SCXtnGJZCEglduxAZI35QY',
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
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
      title: 'Moaner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final StreamSubscription<AuthState> _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      return const MoanPage();
    }
    return const AuthPage();
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
  bool _carMode = false;
  int _gpsUpdates = 0;
  String _gpsDebug = '';
  double _currentForce = 0;
  double _currentSpeed = 0; // km/h
  double _sensitivity = 5.0;
  bool _flash = false;

  // Score system
  double _score = 0;
  double _maxScore = 0;
  static const double _maxScoreLimit = 100.0;
  static const double _decayRate = 15.0; // points per second decay


  @override
  void initState() {
    super.initState();
    _startLoop();
    _startListening();
    _decayTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_score > 0) {
        setState(() {
          _score = (_score - _decayRate * 0.05).clamp(0.0, _maxScoreLimit);
        });
      }
    });
  }

  Timer? _audioTimer;

  double _lastLightVol = -1;
  double _lastMediumVol = -1;
  double _lastIntenseVol = -1;

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

      await _lightPlayer.play(AssetSource('audio/light_loop.mp3'), volume: 0);
      print('[AUDIO] light playing');
      await _mediumPlayer.play(AssetSource('audio/medium_loop.mp3'), volume: 0);
      print('[AUDIO] medium playing');
      await _intensePlayer.play(AssetSource('audio/intense_loop.mp3'), volume: 0);
      print('[AUDIO] intense playing');

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

    // Only update volume if changed meaningfully (reduces audio session churn)
    if ((lightVol - _lastLightVol).abs() > 0.02) {
      _lightPlayer.setVolume(lightVol).catchError((e) => print('[VOL ERR light] $e'));
      _lastLightVol = lightVol;
    }
    if ((mediumVol - _lastMediumVol).abs() > 0.02) {
      _mediumPlayer.setVolume(mediumVol).catchError((e) => print('[VOL ERR medium] $e'));
      _lastMediumVol = mediumVol;
    }
    if ((intenseVol - _lastIntenseVol).abs() > 0.02) {
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

  Future<void> _toggleCarMode() async {
    if (!_carMode) {
      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Turn on Location Services'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      // Check permission
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission required'), backgroundColor: Colors.red),
          );
        }
        return;
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
      ).listen(_onPosition);

      _minSpeedSinceLastTrigger = 0;

      setState(() {
        _carMode = true;
        _gpsUpdates = 0;
      });
    } else {
      // Disable car mode — loop keeps playing, shake takes over
      _positionSub?.cancel();
      _lastPosition = null;
      _currentSpeed = 0;
      _score = 0;
      _startListening();
      setState(() => _carMode = false);
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
    if (dt > 0.2 && dt < 5) {
      accel = (smoothed - _lastSpeedForAccel) / dt;
    }
    _lastSpeedForAccel = smoothed;
    _lastAccelTime = now;

    setState(() {
      _currentSpeed = smoothed;
      _currentForce = smoothed;
      if (accel > 3) {
        final points = (accel - 3) * (accel - 3) * 0.6;
        _score = (_score + points).clamp(0.0, _maxScoreLimit);
        if (_score > _maxScore) _maxScore = _score;
        _flash = true;
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
      final points = (impact / 10.0).clamp(0.5, 5.0);
      setState(() {
        _score = (_score + points).clamp(0.0, _maxScoreLimit);
        if (_score > _maxScore) _maxScore = _score;
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
    return '😩💦💦💦';
  }

  Color _scoreColor() {
    if (_score < 25) return Colors.purple;
    if (_score < 50) return Colors.pink;
    if (_score < 75) return Colors.red;
    return Colors.red.shade200;
  }

  @override
  Widget build(BuildContext context) {
    final scorePct = (_score / _maxScoreLimit).clamp(0.0, 1.0);

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        color: _flash ? _scoreColor().withValues(alpha: 0.3) : Colors.black,
        child: SafeArea(
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Text('😩', style: TextStyle(fontSize: 50)),
                    Positioned(
                      right: 8,
                      child: IconButton(
                        icon: Icon(Icons.logout, color: Colors.white.withValues(alpha: 0.4), size: 20),
                        onPressed: () => Supabase.instance.client.auth.signOut(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const Text('Moaner', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
              Text(_carMode ? 'Drive faster...' : 'Shake or slap your phone',
                  style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.5))),

              const SizedBox(height: 24),

              // Score bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    // Score number + label
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _score.toInt().toString(),
                          style: TextStyle(
                            fontSize: 56,
                            fontWeight: FontWeight.w800,
                            color: _scoreColor(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(_scoreLabel(), style: const TextStyle(fontSize: 28)),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        height: 16,
                        child: Stack(
                          children: [
                            // Background
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            // Fill
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
                        Text('0', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.3))),
                        Text('Best: ${_maxScore.toInt()}', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.3))),
                        Text('100', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.3))),
                      ],
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Force circle
              Container(
                width: 160, height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Color.lerp(Colors.white.withValues(alpha: 0.15), _scoreColor(), scorePct)!,
                    width: 2 + scorePct * 3,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                          _carMode ? _currentSpeed.toInt().toString() : _currentForce.toStringAsFixed(1),
                          style: TextStyle(fontSize: 40, fontWeight: FontWeight.w200,
                              color: Color.lerp(Colors.white.withValues(alpha: 0.4), _scoreColor(), scorePct))),
                      Text(_carMode ? 'km/h' : 'm/s²', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.3))),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              const Spacer(),

              const SizedBox(height: 16),

              // Car mode toggle
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
      ),
    );
  }
}
