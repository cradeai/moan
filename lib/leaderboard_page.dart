import 'package:flutter/material.dart';
import 'leaderboard.dart';

class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key});

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  List<LeaderboardEntry>? _entries;
  String? _modeFilter;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await Leaderboard.fetchTop(limit: 100, mode: _modeFilter);
    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
  }

  void _setFilter(String? mode) {
    setState(() => _modeFilter = mode);
    _load();
  }

  Color _rankColor(int rank) {
    if (rank == 0) return const Color(0xFFFFD700);
    if (rank == 1) return const Color(0xFFC0C0C0);
    if (rank == 2) return const Color(0xFFCD7F32);
    return Colors.white.withValues(alpha: 0.5);
  }

  @override
  Widget build(BuildContext context) {
    final myDeviceId = Leaderboard.deviceId;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Leaderboard'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _filterChip('All', null),
                const SizedBox(width: 8),
                _filterChip('Drive', 'drive'),
                const SizedBox(width: 8),
                _filterChip('Shake', 'shake'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Colors.purple))
                : _entries == null || _entries!.isEmpty
                    ? const Center(
                        child: Text(
                          'No scores yet.\nBe the first!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontSize: 16),
                        ),
                      )
                    : RefreshIndicator(
                        color: Colors.purple,
                        onRefresh: _load,
                        child: ListView.builder(
                          itemCount: _entries!.length,
                          itemBuilder: (context, index) {
                            final entry = _entries![index];
                            final isMe = entry.deviceId == myDeviceId;
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? Colors.purple.withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: isMe
                                    ? Border.all(color: Colors.purple, width: 1.5)
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 32,
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        color: _rankColor(index),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.displayName,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: isMe ? FontWeight.w700 : FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          entry.mode == 'drive' ? 'Drive' : 'Shake',
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.4),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${entry.score}',
                                    style: TextStyle(
                                      color: isMe ? Colors.purpleAccent : Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String? value) {
    final selected = _modeFilter == value;
    return GestureDetector(
      onTap: () => _setFilter(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.purple : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

Future<String?> showDisplayNameDialog(BuildContext context) async {
  final controller = TextEditingController(text: Leaderboard.displayName ?? '');
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.grey.shade900,
      title: const Text('Choose a name', style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 16,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Your leaderboard name',
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white24),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.purple),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final name = controller.text.trim();
            if (name.isNotEmpty) Navigator.of(ctx).pop(name);
          },
          child: const Text('Save', style: TextStyle(color: Colors.purpleAccent)),
        ),
      ],
    ),
  );
}
