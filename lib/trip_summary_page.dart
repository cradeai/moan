import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'trip.dart';

class TripSummaryPage extends StatefulWidget {
  final Trip trip;
  const TripSummaryPage({super.key, required this.trip});

  @override
  State<TripSummaryPage> createState() => _TripSummaryPageState();
}

class _TripSummaryPageState extends State<TripSummaryPage> {
  final ScreenshotController _shotController = ScreenshotController();
  bool _sharing = false;

  List<LatLng> get _polyline =>
      widget.trip.points.map((p) => LatLng(p.lat, p.lng)).toList();

  LatLngBounds? get _bounds {
    if (_polyline.isEmpty) return null;
    double minLat = _polyline.first.latitude;
    double maxLat = _polyline.first.latitude;
    double minLng = _polyline.first.longitude;
    double maxLng = _polyline.first.longitude;
    for (final p in _polyline) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final bytes = await _shotController.capture(
        pixelRatio: 2.5,
        delay: const Duration(milliseconds: 300),
      );
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/trip_${widget.trip.id}.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'My drive: ${widget.trip.peakScore} 🔥 — ${widget.trip.distanceKm.toStringAsFixed(1)} km',
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s}s';
  }

  String _formatDate(DateTime dt) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final hasRoute = _polyline.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Trip Summary'),
        backgroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Screenshot(
              controller: _shotController,
              child: Container(
                color: Colors.black,
                child: Column(
                  children: [
                    SizedBox(
                      height: 280,
                      child: hasRoute
                          ? FlutterMap(
                              options: MapOptions(
                                initialCameraFit: CameraFit.bounds(
                                  bounds: _bounds!,
                                  padding: const EdgeInsets.all(40),
                                ),
                                interactionOptions: const InteractionOptions(
                                  flags: InteractiveFlag.none,
                                ),
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.moan.moan',
                                ),
                                PolylineLayer(
                                  polylines: [
                                    Polyline(
                                      points: _polyline,
                                      strokeWidth: 4,
                                      color: Colors.purpleAccent,
                                    ),
                                  ],
                                ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: _polyline.first,
                                      child: const Icon(Icons.circle, color: Colors.greenAccent, size: 16),
                                    ),
                                    Marker(
                                      point: _polyline.last,
                                      child: const Icon(Icons.flag, color: Colors.redAccent, size: 22),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : Container(
                              color: Colors.grey.shade900,
                              child: const Center(
                                child: Text(
                                  'No route data',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Text(
                            _formatDate(trip.startedAt),
                            style: const TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${trip.peakScore}',
                            style: const TextStyle(
                              fontSize: 72,
                              fontWeight: FontWeight.w800,
                              color: Colors.purpleAccent,
                            ),
                          ),
                          const Text(
                            'Peak Score',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _stat('${trip.distanceKm.toStringAsFixed(1)}', 'km'),
                              _stat('${trip.topSpeedKmh.toInt()}', 'top km/h'),
                              _stat(_formatDuration(trip.durationSec), 'duration'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _sharing ? null : _share,
                  icon: _sharing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.ios_share),
                  label: const Text('Share', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }
}
