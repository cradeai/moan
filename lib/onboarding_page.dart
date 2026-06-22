import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'leaderboard.dart';

class OnboardingPage extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingPage({super.key, required this.onComplete});

  static const _key = 'onboarding_done_v1';

  static Future<bool> hasCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> markComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _controller = PageController();
  final TextEditingController _nameController = TextEditingController();
  int _page = 0;

  static const _infoPages = [
    _PageData(
      icon: Icons.directions_car_filled,
      title: 'Drive Mode',
      body: 'Mount your phone and drive. Real-time GPS detects your acceleration and turns it into a score.',
      color: Colors.purpleAccent,
    ),
    _PageData(
      icon: Icons.vibration,
      title: 'Shake Mode',
      body: 'Not driving? Shake your phone to score points using the built-in motion sensor. Sounds intensify as your score climbs.',
      color: Colors.pinkAccent,
    ),
    _PageData(
      icon: Icons.emoji_events,
      title: 'Compete',
      body: 'Climb the global leaderboard. Filter by Drive or Shake mode. Your best scores are saved automatically.',
      color: Colors.amber,
    ),
    _PageData(
      icon: Icons.shield_outlined,
      title: 'Drive Safely',
      body: 'Mount your phone before driving — never hold it. Best used with a passenger. Stay focused on the road.',
      color: Colors.greenAccent,
    ),
  ];

  int get _totalPages => _infoPages.length + 1;

  @override
  void dispose() {
    _nameController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _totalPages - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish({bool skip = false}) async {
    String name = skip ? '' : _nameController.text.trim();
    if (name.isEmpty) {
      // Random anonymous name like "user 2343"
      final n = Random().nextInt(9000) + 1000;
      name = 'user $n';
    }
    await Leaderboard.setDisplayName(name);
    await OnboardingPage.markComplete();
    if (mounted) widget.onComplete();
  }

  String get _buttonLabel {
    if (_page < _infoPages.length) return 'Next';
    return 'Get Started';
  }

  bool get _isLastPage => _page == _totalPages - 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _totalPages,
                onPageChanged: (p) => setState(() => _page = p),
                itemBuilder: (_, i) {
                  if (i < _infoPages.length) {
                    return _InfoPage(data: _infoPages[i]);
                  }
                  return _NamePage(controller: _nameController);
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_totalPages, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? Colors.purpleAccent : Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    _buttonLabel,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: _isLastPage
                  ? TextButton(
                      onPressed: () => _finish(skip: true),
                      child: Text(
                        'Skip — stay anonymous',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _PageData {
  final IconData icon;
  final String title;
  final String body;
  final Color color;
  const _PageData({required this.icon, required this.title, required this.body, required this.color});
}

class _InfoPage extends StatelessWidget {
  final _PageData data;
  const _InfoPage({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: data.color.withValues(alpha: 0.15),
              border: Border.all(color: data.color, width: 2),
            ),
            child: Icon(data.icon, size: 70, color: data.color),
          ),
          const SizedBox(height: 40),
          Text(
            data.title,
            style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          Text(
            data.body,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _NamePage extends StatelessWidget {
  final TextEditingController controller;
  const _NamePage({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.purpleAccent.withValues(alpha: 0.15),
              border: Border.all(color: Colors.purpleAccent, width: 2),
            ),
            child: const Icon(Icons.person_outline, size: 70, color: Colors.purpleAccent),
          ),
          const SizedBox(height: 40),
          const Text(
            'Your Driver Name',
            style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          Text(
            'Your name on the leaderboard.\nBeat your friends\' scores.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16, height: 1.5),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: controller,
            maxLength: 16,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'Enter a name',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontWeight: FontWeight.w400),
              counterText: '',
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.purpleAccent, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'You can change this anytime in Settings.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
          ),
        ],
      ),
    );
  }
}
