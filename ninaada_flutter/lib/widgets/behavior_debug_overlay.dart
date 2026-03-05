import 'dart:math' show min;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ninaada_music/services/behavior_engine.dart';

// ════════════════════════════════════════════════════════════════
//  BEHAVIOR DEBUG OVERLAY — Phase 9C, Step 13
// ════════════════════════════════════════════════════════════════
//
//  Dev-only floating overlay showing real-time BehaviorEngine state.
//  Only visible in debug builds (kDebugMode guard).
//
//  Shows:
//    • Dynamic epsilon (ε) and what's driving it
//    • Recent skip rate / full-play rate
//    • Current song affinity
//    • Top behavioral artists/languages
//    • Last 5 events compact view
//    • Onboarding weight
//    • Total events processed
//
// ════════════════════════════════════════════════════════════════

class BehaviorDebugOverlay extends StatefulWidget {
  const BehaviorDebugOverlay({super.key});

  @override
  State<BehaviorDebugOverlay> createState() => _BehaviorDebugOverlayState();
}

class _BehaviorDebugOverlayState extends State<BehaviorDebugOverlay> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    // Only show in debug mode
    if (!kDebugMode) return const SizedBox.shrink();

    // Guard: BehaviorEngine may not be initialized yet
    if (!BehaviorEngine.isInitialized) return const SizedBox.shrink();

    final be = BehaviorEngine.instance;

    return Positioned(
      top: 100,
      right: 8,
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          color: Colors.black87,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _expanded ? 280 : 48,
            padding: const EdgeInsets.all(8),
            child: _expanded ? _buildExpanded(be) : _buildCollapsed(be),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsed(BehaviorEngine be) {
    final eps = be.currentEpsilon;
    final color = eps >= 0.30
        ? Colors.orange
        : eps <= 0.12
            ? Colors.green
            : Colors.blue;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.psychology, color: color, size: 20),
        Text(
          'ε${eps.toStringAsFixed(2)}',
          style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildExpanded(BehaviorEngine be) {
    final summary = be.debugSummary;
    final eps = be.currentEpsilon;
    final epsLabel = eps >= 0.30
        ? 'EXPLORE'
        : eps <= 0.12
            ? 'EXPLOIT'
            : 'BALANCED';
    final epsColor = eps >= 0.30
        ? Colors.orange
        : eps <= 0.12
            ? Colors.green
            : Colors.blue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Row(
          children: [
            Icon(Icons.psychology, color: epsColor, size: 16),
            const SizedBox(width: 4),
            Text(
              'Behavior Engine',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Text(
              'ε=${eps.toStringAsFixed(2)} $epsLabel',
              style: TextStyle(color: epsColor, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const Divider(color: Colors.white24, height: 8),

        // Stats row
        _statRow('Events', '${summary['totalEvents']} (buf: ${summary['bufferedEvents']})'),
        _statRow('Skip Rate', '${(be.recentSkipRate * 100).toInt()}%'),
        _statRow('Full Play', '${(be.recentFullPlayRate * 100).toInt()}%'),
        _statRow('OB Weight', '${be.onboardingWeight.toStringAsFixed(2)}×'),
        _statRow('Song Affinities', '${summary['songAffinities']}'),
        _statRow('Artist Scores', '${summary['artistScores']}'),

        const SizedBox(height: 4),

        // Top artists
        if ((summary['topArtists'] as List).isNotEmpty) ...[
          Text('Top Artists:', style: TextStyle(color: Colors.white54, fontSize: 9)),
          ...(summary['topArtists'] as List<MapEntry<String, double>>)
              .take(3)
              .map((e) => Text(
                    '  ${_truncate(e.key, 18)}: ${e.value.toStringAsFixed(1)}',
                    style: const TextStyle(color: Colors.white38, fontSize: 9),
                  )),
        ],

        const SizedBox(height: 4),

        // Recent events
        if ((summary['recentEvents'] as List).isNotEmpty) ...[
          Text('Recent:', style: TextStyle(color: Colors.white54, fontSize: 9)),
          ...(summary['recentEvents'] as List)
              .take(5)
              .map((e) => Text(
                    '  $e',
                    style: const TextStyle(color: Colors.white38, fontSize: 9),
                  )),
        ],
      ],
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          Text(value, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }

  String _truncate(String s, int maxLen) {
    if (s.length <= maxLen) return s;
    return '${s.substring(0, maxLen)}...';
  }
}
