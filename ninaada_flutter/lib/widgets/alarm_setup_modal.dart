import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/providers/app_providers.dart';
import 'package:ninaada_music/providers/sleep_alarm_provider.dart';

// ================================================================
//  ALARM SETUP MODAL
// ================================================================
//
//  Full alarm configuration sheet:
//    ┌──────────────────────────────────────────┐
//    │            Wake-Up Alarm                 │
//    │                                          │
//    │  ── Enable ────────────────── [toggle]   │
//    │                                          │
//    │  ── Time ──                              │
//    │  [ 07 : 00 ]   (tap to change)          │
//    │                                          │
//    │  ── Playlist ──                          │
//    │  [dropdown / list of user playlists]     │
//    │                                          │
//    │  ── Volume ──                            │
//    │  [========|======] 0.7                   │
//    │                                          │
//    │  ── Progressive Volume ────── [toggle]   │
//    │  Ramp duration: [30s] [60s] [120s]      │
//    └──────────────────────────────────────────┘
// ================================================================

/// Show the alarm setup as a modal bottom sheet.
void showAlarmSetupModal(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: NinaadaColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const AlarmSetupModal(),
  );
}

class AlarmSetupModal extends ConsumerWidget {
  const AlarmSetupModal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarm = ref.watch(sleepAlarmProvider);
    final playlists = ref.watch(libraryProvider).playlists;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle bar ──
          Container(
            width: 32,
            height: 3,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),

          // ── Title ──
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.alarm, size: 20, color: NinaadaColors.primaryLight),
              const SizedBox(width: 8),
              const Text(
                'Wake-Up Alarm',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ═══════════════════════════════════════
          //  ENABLE TOGGLE
          // ═══════════════════════════════════════
          _ToggleRow(
            icon: Icons.alarm_on,
            label: 'Enable Alarm',
            subtitle: alarm.alarmEnabled
                ? 'Set for ${alarm.alarmDisplay}'
                : 'Off',
            value: alarm.alarmEnabled,
            onChanged: (v) =>
                ref.read(sleepAlarmProvider.notifier).setAlarmEnabled(v),
          ),

          if (alarm.alarmEnabled) ...[
            const SizedBox(height: 16),

            // ═══════════════════════════════════════
            //  TIME PICKER
            // ═══════════════════════════════════════
            GestureDetector(
              onTap: () => _pickTime(context, ref, alarm),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 16, horizontal: 24),
                decoration: BoxDecoration(
                  color: NinaadaColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: NinaadaColors.primary.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.access_time,
                        size: 20,
                        color: NinaadaColors.primaryLight),
                    const SizedBox(width: 12),
                    Text(
                      alarm.alarmDisplay,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w200,
                        letterSpacing: 3,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.edit,
                        size: 14,
                        color: Colors.white.withOpacity(0.3)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ═══════════════════════════════════════
            //  PLAYLIST SELECTOR
            // ═══════════════════════════════════════
            _SectionLabel(label: 'Wake-Up Playlist'),
            const SizedBox(height: 8),
            _PlaylistPicker(
              playlists: playlists,
              selectedId: alarm.alarmPlaylistId,
              onSelected: (id) =>
                  ref.read(sleepAlarmProvider.notifier).setAlarmPlaylist(id),
            ),

            const SizedBox(height: 16),

            // ═══════════════════════════════════════
            //  VOLUME SLIDER
            // ═══════════════════════════════════════
            _SectionLabel(label: 'Alarm Volume'),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.volume_down,
                    size: 18, color: Colors.white.withOpacity(0.4)),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: NinaadaColors.primary,
                      inactiveTrackColor:
                          NinaadaColors.primary.withOpacity(0.15),
                      thumbColor: NinaadaColors.primaryLight,
                      overlayColor:
                          NinaadaColors.primary.withOpacity(0.1),
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: alarm.alarmVolume,
                      min: 0.1,
                      max: 1.0,
                      onChanged: (v) => ref
                          .read(sleepAlarmProvider.notifier)
                          .setAlarmVolume(v),
                    ),
                  ),
                ),
                Icon(Icons.volume_up,
                    size: 18, color: Colors.white.withOpacity(0.4)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${(alarm.alarmVolume * 100).round()}%',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ═══════════════════════════════════════
            //  PROGRESSIVE VOLUME
            // ═══════════════════════════════════════
            _ToggleRow(
              icon: Icons.trending_up,
              label: 'Progressive Volume',
              subtitle: 'Gradually increase volume',
              value: alarm.progressiveVolume,
              onChanged: (v) => ref
                  .read(sleepAlarmProvider.notifier)
                  .setProgressiveVolume(v),
            ),
            if (alarm.progressiveVolume) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final dur in [30, 60, 120])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: GestureDetector(
                        onTap: () => ref
                            .read(sleepAlarmProvider.notifier)
                            .setAlarmFadeDuration(dur),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 6, horizontal: 16),
                          decoration: BoxDecoration(
                            color: alarm.alarmFadeDuration == dur
                                ? NinaadaColors.primary.withOpacity(0.15)
                                : Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: alarm.alarmFadeDuration == dur
                                  ? NinaadaColors.primary
                                      .withOpacity(0.4)
                                  : Colors.white.withOpacity(0.08),
                            ),
                          ),
                          child: Text(
                            '${dur}s',
                            style: TextStyle(
                              color: alarm.alarmFadeDuration == dur
                                  ? NinaadaColors.primaryLight
                                  : Colors.white.withOpacity(0.5),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _pickTime(
      BuildContext context, WidgetRef ref, SleepAlarmState alarm) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: alarm.alarmHour, minute: alarm.alarmMinute),
      builder: (ctx, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: NinaadaColors.primary,
              surface: NinaadaColors.surface,
              onSurface: Colors.white,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: NinaadaColors.surface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      ref
          .read(sleepAlarmProvider.notifier)
          .setAlarmTime(picked.hour, picked.minute);
    }
  }
}

// ════════════════════════════════════════════════
//  SHARED SUB-WIDGETS
// ════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withOpacity(0.4),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white.withOpacity(0.5)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.35),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 24,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeColor: NinaadaColors.primary,
              activeTrackColor: NinaadaColors.primary.withOpacity(0.3),
              inactiveThumbColor: Colors.white.withOpacity(0.4),
              inactiveTrackColor: Colors.white.withOpacity(0.1),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal scrollable playlist picker for alarm source.
class _PlaylistPicker extends StatelessWidget {
  final List<PlaylistModel> playlists;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  const _PlaylistPicker({
    required this.playlists,
    this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (playlists.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.library_music,
                size: 16, color: Colors.white.withOpacity(0.3)),
            const SizedBox(width: 8),
            Text(
              'No playlists — will use trending songs',
              style: TextStyle(
                color: Colors.white.withOpacity(0.35),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: playlists.length + 1, // +1 for "Random" option
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          // First item = "Trending" / no playlist
          if (index == 0) {
            final isSel = selectedId == null;
            return GestureDetector(
              onTap: () => onSelected(null),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSel
                      ? NinaadaColors.primary.withOpacity(0.15)
                      : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSel
                        ? NinaadaColors.primary.withOpacity(0.4)
                        : Colors.white.withOpacity(0.08),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.trending_up,
                        size: 14,
                        color: isSel
                            ? NinaadaColors.primaryLight
                            : Colors.white.withOpacity(0.5)),
                    const SizedBox(width: 6),
                    Text(
                      'Trending',
                      style: TextStyle(
                        color: isSel
                            ? NinaadaColors.primaryLight
                            : Colors.white.withOpacity(0.6),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final pl = playlists[index - 1];
          final isSel = selectedId == pl.id;
          return GestureDetector(
            onTap: () => onSelected(pl.id),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSel
                    ? NinaadaColors.primary.withOpacity(0.15)
                    : Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSel
                      ? NinaadaColors.primary.withOpacity(0.4)
                      : Colors.white.withOpacity(0.08),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.queue_music,
                      size: 14,
                      color: isSel
                          ? NinaadaColors.primaryLight
                          : Colors.white.withOpacity(0.5)),
                  const SizedBox(width: 6),
                  Text(
                    pl.name,
                    style: TextStyle(
                      color: isSel
                          ? NinaadaColors.primaryLight
                          : Colors.white.withOpacity(0.6),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
