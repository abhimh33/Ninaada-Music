import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/core/helpers.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/providers/sleep_alarm_provider.dart';

// ================================================================
//  ENHANCED SLEEP TIMER MODAL — Shared widget
// ================================================================
//
//  Used by both player_screen._ActionRow and media_action_sheet.
//  Matches the RN EnhancedSleepTimerModal pixel-for-pixel:
//
//    ┌──────────────────────────────────────┐
//    │           Sleep Timer                │
//    │  [5] [10] [15] [20] [30] [45]       │
//    │  [60] [90] [Custom] [End of Song]   │
//    │                                      │
//    │  ── Fade Out ──────────── [toggle]   │
//    │  [15s]  [30s]  [60s]                │
//    │                                      │
//    │  ── Ambient Dim ────────  [toggle]   │
//    └──────────────────────────────────────┘
//
//  When active, shows countdown + cancel button instead.
// ================================================================

/// Show the enhanced sleep timer as a modal bottom sheet.
void showSleepTimerModal(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: NinaadaColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const EnhancedSleepTimerModal(),
  );
}

class EnhancedSleepTimerModal extends ConsumerStatefulWidget {
  const EnhancedSleepTimerModal({super.key});

  @override
  ConsumerState<EnhancedSleepTimerModal> createState() =>
      _EnhancedSleepTimerModalState();
}

class _EnhancedSleepTimerModalState
    extends ConsumerState<EnhancedSleepTimerModal> {
  final _customController = TextEditingController();
  bool _showCustomInput = false;

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _startTimer(int minutes) {
    ref.read(sleepAlarmProvider.notifier).startSleep(minutes);
    Navigator.pop(context);
  }

  void _submitCustom() {
    final val = int.tryParse(_customController.text.trim());
    if (val != null && val > 0 && val <= 720) {
      _startTimer(val);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sleep = ref.watch(sleepAlarmProvider);
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
              Icon(Icons.nightlight_round,
                  size: 20, color: NinaadaColors.primaryLight),
              const SizedBox(width: 8),
              const Text(
                'Sleep Timer',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ═══════════════════════════════════════
          //  ACTIVE STATE — countdown + cancel
          // ═══════════════════════════════════════
          if (sleep.sleepActive) ...[
            // Countdown display
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              decoration: BoxDecoration(
                color: NinaadaColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: NinaadaColors.primary.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  if (sleep.endOfSong)
                    const Text(
                      'Stopping after current song',
                      style: TextStyle(
                        color: NinaadaColors.primaryLight,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else ...[
                    Text(
                      sleep.sleepDisplay,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w200,
                        letterSpacing: 2,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'remaining',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (sleep.fadeOutEnabled) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.volume_off,
                            size: 12,
                            color: Colors.white.withOpacity(0.3)),
                        const SizedBox(width: 4),
                        Text(
                          'Fade out ${sleep.fadeOutDuration}s',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (sleep.ambientDimEnabled) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.brightness_2,
                            size: 12,
                            color: Colors.white.withOpacity(0.3)),
                        const SizedBox(width: 4),
                        Text(
                          'Screen dimming active',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Cancel button
            GestureDetector(
              onTap: () {
                ref.read(sleepAlarmProvider.notifier).startSleep(0);
                Navigator.pop(context);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 28),
                decoration: BoxDecoration(
                  color: NinaadaColors.error.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: NinaadaColors.error.withOpacity(0.3)),
                ),
                child: const Text(
                  'Cancel Timer',
                  style: TextStyle(
                    color: NinaadaColors.error,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ]

          // ═══════════════════════════════════════
          //  INACTIVE STATE — preset grid + options
          // ═══════════════════════════════════════
          else ...[
            // Duration presets
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final min in [5, 10, 15, 20, 30, 45, 60, 90])
                  _PresetChip(
                    label: '$min min',
                    onTap: () => _startTimer(min),
                  ),
                // Custom
                _PresetChip(
                  label: 'Custom',
                  icon: Icons.edit,
                  highlighted: _showCustomInput,
                  onTap: () => setState(() {
                    _showCustomInput = !_showCustomInput;
                  }),
                ),
                // End of Song
                _PresetChip(
                  label: 'End of Song',
                  icon: Icons.music_note,
                  accent: true,
                  onTap: () => _startTimer(-1),
                ),
              ],
            ),

            // Custom input field
            if (_showCustomInput) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: NinaadaColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: NinaadaColors.border),
                      ),
                      child: TextField(
                        controller: _customController,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Minutes (1-720)',
                          hintStyle: TextStyle(
                              color: Colors.white.withOpacity(0.25),
                              fontSize: 13),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _submitCustom(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _submitCustom,
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: NinaadaColors.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: NinaadaColors.primary.withOpacity(0.3)),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Start',
                        style: TextStyle(
                          color: NinaadaColors.primaryLight,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 20),

            // ── Fade Out toggle + duration chips ──
            _SettingRow(
              icon: Icons.volume_off_outlined,
              label: 'Fade Out',
              value: sleep.fadeOutEnabled,
              onChanged: (v) =>
                  ref.read(sleepAlarmProvider.notifier).setFadeOutEnabled(v),
            ),
            if (sleep.fadeOutEnabled) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final dur in [15, 30, 60])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: GestureDetector(
                        onTap: () => ref
                            .read(sleepAlarmProvider.notifier)
                            .setFadeOutDuration(dur),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 6, horizontal: 16),
                          decoration: BoxDecoration(
                            color: sleep.fadeOutDuration == dur
                                ? NinaadaColors.primary.withOpacity(0.15)
                                : Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: sleep.fadeOutDuration == dur
                                  ? NinaadaColors.primary.withOpacity(0.4)
                                  : Colors.white.withOpacity(0.08),
                            ),
                          ),
                          child: Text(
                            '${dur}s',
                            style: TextStyle(
                              color: sleep.fadeOutDuration == dur
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

            const SizedBox(height: 12),

            // ── Ambient Dim toggle ──
            _SettingRow(
              icon: Icons.dark_mode_outlined,
              label: 'Ambient Dim',
              subtitle: 'Gradually darken screen',
              value: sleep.ambientDimEnabled,
              onChanged: (v) =>
                  ref.read(sleepAlarmProvider.notifier).setAmbientDimEnabled(v),
            ),
          ],
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════
//  SHARED SUB-WIDGETS
// ════════════════════════════════════════════════

/// Pill chip for preset duration selection.
class _PresetChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool accent;
  final bool highlighted;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    this.icon,
    this.accent = false,
    this.highlighted = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isAccent = accent || highlighted;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 18),
        decoration: BoxDecoration(
          color: isAccent
              ? NinaadaColors.primary.withOpacity(0.12)
              : NinaadaColors.surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isAccent
                ? NinaadaColors.primary.withOpacity(0.3)
                : NinaadaColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 14,
                  color: isAccent
                      ? NinaadaColors.primaryLight
                      : Colors.white.withOpacity(0.6)),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: isAccent
                    ? NinaadaColors.primaryLight
                    : Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Toggle row for settings (Fade Out, Ambient Dim, etc.)
class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingRow({
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
