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
      title: 'Moan',
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
  final AudioPlayer _player = AudioPlayer();

  bool _enabled = true;
  bool _carMode = false;
  int _gpsUpdates = 0;
  String _gpsDebug = '';
  double _currentForce = 0;
  double _currentSpeed = 0; // km/h
  double _sensitivity = 3.0;
  bool _flash = false;

  // Score system
  double _score = 0;
  double _maxScore = 0;
  static const double _maxScoreLimit = 100.0;
  static const double _decayRate = 8.0; // points per second decay


  @override
  void initState() {
    super.initState();
    _startLoop();
    _startListening();
    _decayTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_score > 0 && !_carMode) {
        setState(() {
          _score = (_score - _decayRate * 0.05).clamp(0.0, _maxScoreLimit);
        });
      }
    });
  }

  Timer? _audioTimer;
  bool _isPlayingMoan = false;
  double _peakScore = 0;
  double _currentVolume = 0;

  Future<void> _startLoop() async {
    await _player.setReleaseMode(ReleaseMode.stop);

    _player.onPlayerComplete.listen((_) {
      _isPlayingMoan = false;
      _currentVolume = 0;
      print('[COMPLETE] file ended');
    });

    // Fade out manager — only touches volume, never triggers play
    _audioTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!_isPlayingMoan) return;

      final msSinceTrigger = DateTime.now().difference(_triggerTime).inMilliseconds;
      final shouldFade = _score < _peakScore - 2 || msSinceTrigger > _fadeAfterMs;

      if (_score > _peakScore) {
        // Score still rising → update peak, reset timer, keep full volume
        _peakScore = _score;
        _triggerTime = DateTime.now();
        final factor = (_score / _maxScoreLimit).clamp(0.0, 1.0);
        _currentVolume = (0.3 + factor * 0.7).clamp(0.3, 1.0);
        _player.setVolume(_currentVolume);
        print('[RISE] score=${_score.toStringAsFixed(1)} peak=${_peakScore.toStringAsFixed(1)} vol=${_currentVolume.toStringAsFixed(2)}');
      } else if (shouldFade) {
        // Score dropping or no rise for 3s → fade out
        _currentVolume = (_currentVolume * 0.97);
        if (_currentVolume < 0.005) {
          _currentVolume = 0;
          _player.stop();
          _isPlayingMoan = false;
          print('[STOP] fade out complete');
        } else {
          _player.setVolume(_currentVolume);
          print('[FADE] score=${_score.toStringAsFixed(1)} peak=${_peakScore.toStringAsFixed(1)} vol=${_currentVolume.toStringAsFixed(3)}');
        }
      }
    });
  }

  DateTime _triggerTime = DateTime.now();
  static const int _fadeAfterMs = 3000; // start fade 3s after trigger if no new rise

  void _triggerMoan(double factor) {
    if (_isPlayingMoan) return;
    final rate = 0.5 + factor * 1.5;
    _currentVolume = (0.3 + factor * 0.7).clamp(0.3, 1.0);
    _peakScore = _score;
    _triggerTime = DateTime.now();
    _isPlayingMoan = true;
    _player.setPlaybackRate(rate);
    _player.setVolume(_currentVolume);
    _player.play(AssetSource('audio/moan.mp3'));
    print('[TRIGGER] score=${_score.toStringAsFixed(1)} factor=${factor.toStringAsFixed(2)} rate=${rate.toStringAsFixed(2)} vol=${_currentVolume.toStringAsFixed(2)}');
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _positionSub?.cancel();
    _decayTimer?.cancel();
    _audioTimer?.cancel();
    _player.dispose();
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
    if (jump >= _speedJumpThreshold && !_isPlayingMoan) {
      _minSpeedSinceLastTrigger = smoothed;
      _minSpeedTime = DateTime.now();
      // Intensity based on how fast we're going now
      final factor = (smoothed / 150.0).clamp(0.0, 1.0);
      _triggerMoan(factor);
    }

    setState(() {
      _currentSpeed = smoothed;
      _currentForce = smoothed;
      _score = smoothed.clamp(0.0, _maxScoreLimit);
      if (_score > _maxScore) _maxScore = _score;
      _gpsDebug = 'GPS #$_gpsUpdates | ${speedKmh.toStringAsFixed(0)} km/h | jump: ${jump.toStringAsFixed(0)}';
    });
  }

  void _onMotion(UserAccelerometerEvent event) {
    if (_carMode) return;
    final impact = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    setState(() => _currentForce = impact);

    if (!_enabled) return;

    if (impact > _sensitivity) {
      final points = (impact / 3.0).clamp(1.0, 15.0);
      setState(() {
        _score = (_score + points).clamp(0.0, _maxScoreLimit);
        if (_score > _maxScore) _maxScore = _score;
        _flash = true;
      });

      // Trigger immediately on shake
      final factor = (_score / _maxScoreLimit).clamp(0.0, 1.0);
      _triggerMoan(factor);

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
              Stack(
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
              const SizedBox(height: 4),
              const Text('Moan', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
              Text(_carMode ? 'Drive faster...' : 'Shake or slap your phone',
                  style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.5))),
              if (_carMode && _gpsDebug.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_gpsDebug, style: TextStyle(fontSize: 10, color: Colors.green.withValues(alpha: 0.6))),
                ),

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

              // Test slider
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  children: [
                    Text('Test Score', style: TextStyle(fontSize: 13, color: Colors.orange.withValues(alpha: 0.5))),
                    Slider(
                      value: _score, min: 0, max: 100,
                      activeColor: Colors.orange,
                      inactiveColor: Colors.white.withValues(alpha: 0.1),
                      onChanged: (v) {
                        final oldScore = _score;
                        setState(() => _score = v);
                        if (v > oldScore + 5) {
                          final factor = (v / _maxScoreLimit).clamp(0.0, 1.0);
                          _triggerMoan(factor);
                        }
                      },
                    ),
                  ],
                ),
              ),

              // Sensitivity (only in shake mode)
              if (!_carMode)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    children: [
                      Text('Sensitivity', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5))),
                      Slider(
                        value: _sensitivity, min: 1.0, max: 15.0,
                        activeColor: Colors.purple,
                        inactiveColor: Colors.white.withValues(alpha: 0.1),
                        onChanged: (v) => setState(() => _sensitivity = v),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Sensitive', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.3))),
                          Text('Hard', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.3))),
                        ],
                      ),
                    ],
                  ),
                ),

              if (_carMode) const SizedBox(height: 16),

              const SizedBox(height: 8),

              // Car mode toggle
              GestureDetector(
                onTap: () {
                  _toggleCarMode();
                  HapticFeedback.mediumImpact();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: _carMode ? Colors.orange.shade800 : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.directions_car, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _carMode ? 'Car Mode ON' : 'Car Mode',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Pause/Listen toggle
              GestureDetector(
                onTap: () {
                  setState(() => _enabled = !_enabled);
                  HapticFeedback.mediumImpact();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  decoration: BoxDecoration(
                    color: _enabled ? Colors.purple : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    _enabled ? (_carMode ? 'Driving...' : 'Listening...') : 'Paused',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
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
