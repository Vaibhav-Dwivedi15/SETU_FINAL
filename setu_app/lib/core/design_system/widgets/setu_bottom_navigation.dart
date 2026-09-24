import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_typography.dart';

class SetuBottomNavigation extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const SetuBottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = isDark ? AppColors.bgSidebar : Colors.white;
    final borderColor = isDark ? AppColors.borderSubtle : AppColors.lightBorder;
    final selectedColor = isDark ? AppColors.accent : AppColors.primary;
    final unselectedColor = isDark ? AppColors.textDim : AppColors.lightTextDim;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          top: BorderSide(color: borderColor, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _buildNavItem(
                index: 0,
                icon: Icons.emergency_outlined,
                activeIcon: Icons.emergency_rounded,
                label: 'SOS / Home',
                selectedColor: selectedColor,
                unselectedColor: unselectedColor,
              ),
              _buildNavItem(
                index: 1,
                icon: Icons.health_and_safety_outlined,
                activeIcon: Icons.health_and_safety_rounded,
                label: 'Prepare',
                selectedColor: selectedColor,
                unselectedColor: unselectedColor,
              ),
              _buildNavItem(
                index: 2,
                icon: Icons.restore_outlined,
                activeIcon: Icons.restore_rounded,
                label: 'Recovery',
                selectedColor: selectedColor,
                unselectedColor: unselectedColor,
              ),
              _buildNavItem(
                index: 3,
                icon: Icons.history_outlined,
                activeIcon: Icons.history_rounded,
                label: 'History',
                selectedColor: selectedColor,
                unselectedColor: unselectedColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required Color selectedColor,
    required Color unselectedColor,
  }) {
    final isSelected = currentIndex == index;
    final color = isSelected ? selectedColor : unselectedColor;

    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: label,
        child: InkWell(
          onTap: () => onTap(index),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                color: color,
                size: 22,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: AppTypography.metadata.copyWith(
                  color: color,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 10.5,
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
