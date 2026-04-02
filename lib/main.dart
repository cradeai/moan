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
  Timer? _carMoanTimer;
  final AudioPlayer _player = AudioPlayer();
  final Random _random = Random();

  bool _enabled = true;
  bool _cooldown = false;
  bool _carMode = false;
  int _gpsUpdates = 0;
  String _gpsDebug = '';
  int _moanCount = 0;
  double _currentForce = 0;
  double _currentSpeed = 0; // km/h
  double _sensitivity = 3.0;
  bool _flash = false;

  // Score system
  double _score = 0;
  double _maxScore = 0;
  static const double _maxScoreLimit = 100.0;
  static const double _decayRate = 8.0; // points per second decay
  static const double _maxSpeed = 100.0; // km/h for max intensity

  static const int _totalSounds = 60;

  @override
  void initState() {
    super.initState();
    _startListening();
    _decayTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_score > 0 && !_carMode) {
        setState(() {
          _score = (_score - _decayRate * 0.05).clamp(0.0, _maxScoreLimit);
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _positionSub?.cancel();
    _decayTimer?.cancel();
    _carMoanTimer?.cancel();
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

      // Periodically trigger moans based on speed
      _carMoanTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
        if (!_enabled || _currentSpeed < 3) return;
        final speedFactor = (_currentSpeed / _maxSpeed).clamp(0.0, 1.0);
        final volume = (0.3 + speedFactor * 0.7).clamp(0.3, 1.0);
        final impact = _currentSpeed / 10.0;

        setState(() {
          _moanCount++;
          _score = (speedFactor * _maxScoreLimit).clamp(0.0, _maxScoreLimit);
          if (_score > _maxScore) _maxScore = _score;
          _flash = true;
        });

        _playMoan(volume, impact);

        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _flash = false);
        });
      });

      setState(() {
        _carMode = true;
        _gpsUpdates = 0;
      });
    } else {
      // Disable car mode
      _positionSub?.cancel();
      _carMoanTimer?.cancel();
      _lastPosition = null;
      _currentSpeed = 0;
      _score = 0;
      _startListening();
      setState(() => _carMode = false);
    }
  }

  Position? _lastPosition;

  void _onPosition(Position position) {
    double speedKmh = 0;
    _gpsUpdates++;

    if (position.speed > 0.5) {
      // GPS reports speed reliably above ~0.5 m/s (~2 km/h)
      speedKmh = position.speed * 3.6;
    } else if (_lastPosition != null) {
      // Fallback: calculate from two consecutive positions
      final dist = Geolocator.distanceBetween(
        _lastPosition!.latitude, _lastPosition!.longitude,
        position.latitude, position.longitude,
      );
      final timeSec = position.timestamp.difference(_lastPosition!.timestamp).inMilliseconds / 1000.0;

      if (timeSec > 0.3 && timeSec < 10) {
        final calculated = (dist / timeSec) * 3.6;
        // Ignore GPS noise: if calculated speed jumps unrealistically, cap it
        if (calculated < _currentSpeed + 30 || _currentSpeed == 0) {
          speedKmh = calculated;
        } else {
          speedKmh = _currentSpeed; // keep previous
        }
      }
    }

    _lastPosition = position;
    speedKmh = speedKmh.clamp(0.0, 300.0);

    // Light smoothing for stable display
    final smoothed = _currentSpeed * 0.3 + speedKmh * 0.7;

    setState(() {
      _currentSpeed = smoothed;
      _currentForce = smoothed;
      _gpsDebug = 'GPS #$_gpsUpdates | raw: ${position.speed.toStringAsFixed(2)} m/s | ${speedKmh.toStringAsFixed(1)} km/h | acc: ${position.accuracy.toStringAsFixed(0)}m';
    });
  }

  void _onMotion(UserAccelerometerEvent event) {
    if (_carMode) return;
    final impact = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    setState(() => _currentForce = impact);

    if (!_enabled || _cooldown) return;

    if (impact > _sensitivity) {
      _cooldown = true;

      // Add to score proportional to force
      final points = (impact / 3.0).clamp(1.0, 15.0);
      setState(() {
        _moanCount++;
        _score = (_score + points).clamp(0.0, _maxScoreLimit);
        if (_score > _maxScore) _maxScore = _score;
        _flash = true;
      });

      final volume = (impact / 20.0).clamp(0.3, 1.0);
      _playMoan(volume, impact);

      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _flash = false);
      });
      Future.delayed(const Duration(milliseconds: 400), () => _cooldown = false);
    }
  }

  Future<void> _playMoan(double volume, double impact) async {
    try {
      // Escalation: harder impact → higher index → more intense sound
      final normalized = (1.0 - exp(-impact / 8.0)).clamp(0.0, 1.0);
      final baseIdx = (normalized * (_totalSounds - 1)).round();
      // Add slight randomness (±3) to keep it varied
      final jitter = _random.nextInt(7) - 3;
      final idx = (baseIdx + jitter).clamp(0, _totalSounds - 1);
      await _player.setVolume(volume);
      await _player.play(AssetSource('audio/moan/$idx.mp3'));
    } catch (_) {}
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

              // Moan counter
              Text('$_moanCount', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white)),
              Text(_moanCount == 1 ? 'moan' : 'moans', style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.5))),

              const Spacer(),

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
