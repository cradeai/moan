import 'package:flutter/material.dart';
import 'trip.dart';
import 'trip_summary_page.dart';

class TripHistoryPage extends StatefulWidget {
  const TripHistoryPage({super.key});

  @override
  State<TripHistoryPage> createState() => _TripHistoryPageState();
}

class _TripHistoryPageState extends State<TripHistoryPage> {
  List<Trip>? _trips;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final trips = await TripStore.loadAll();
    if (mounted) setState(() => _trips = trips);
  }

  String _formatDate(DateTime dt) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _delete(Trip trip) async {
    await TripStore.delete(trip.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final trips = _trips;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Trip History'),
        backgroundColor: Colors.black,
      ),
      body: trips == null
          ? const Center(child: CircularProgressIndicator(color: Colors.purple))
          : trips.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No trips yet.\nDrive at least 30 seconds and 100 meters to save a trip.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 15),
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: Colors.purple,
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: trips.length,
                    padding: const EdgeInsets.all(12),
                    itemBuilder: (context, index) {
                      final trip = trips[index];
                      return Dismissible(
                        key: ValueKey(trip.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          decoration: BoxDecoration(
                            color: Colors.red.shade900,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => _delete(trip),
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => TripSummaryPage(trip: trip)),
                          ),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: Colors.purple.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${trip.peakScore}',
                                      style: const TextStyle(
                                        color: Colors.purpleAccent,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _formatDate(trip.startedAt),
                                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${trip.distanceKm.toStringAsFixed(1)} km · ${trip.topSpeedKmh.toInt()} km/h · ${(trip.durationSec / 60).toStringAsFixed(0)}m',
                                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.3)),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
