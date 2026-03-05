import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/providers/app_providers.dart';

/// Bottom navigation bar — 5 tabs: Home, Explore, Player, Library, Radio
/// Matches RN BottomNav exactly: height 70, transparent bg, purple active color
class BottomNavBar extends ConsumerWidget {
  const BottomNavBar({super.key});

  static const _tabs = [
    _NavItem(tab: AppTab.home, icon: Icons.home, label: 'Home'),
    _NavItem(tab: AppTab.explore, icon: Icons.explore_outlined, activeIcon: Icons.explore, label: 'Explore'),
    _NavItem(tab: AppTab.library, icon: Icons.library_music_outlined, activeIcon: Icons.library_music, label: 'Library'),
    _NavItem(tab: AppTab.radio, icon: Icons.radio_outlined, activeIcon: Icons.radio, label: 'Radio'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(navigationProvider);

    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: const Color(0xFF101528),
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(0.06),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: _tabs.map((item) {
          final isActive = nav.currentTab == item.tab;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => ref.read(navigationProvider.notifier).goTab(item.tab),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isActive ? (item.activeIcon ?? item.icon) : item.icon,
                    size: 22,
                    color: isActive ? NinaadaColors.primary : const Color(0xFF666666),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    style: TextStyle(
                      color: isActive ? NinaadaColors.primary : const Color(0xFF666666),
                      fontSize: 9,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _NavItem {
  final AppTab tab;
  final IconData icon;
  final IconData? activeIcon;
  final String label;

  const _NavItem({
    required this.tab,
    required this.icon,
    this.activeIcon,
    required this.label,
  });
}
