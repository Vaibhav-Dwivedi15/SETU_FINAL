// =====================================================
// SETU Project
// Module : Child Safety Mode (Redesign)
// =====================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';

import '../../data/models/child_profile_model.dart';
import '../../data/repositories/child_safety_repository.dart';

class ChildSafetyListScreen extends StatefulWidget {
  const ChildSafetyListScreen({super.key});

  @override
  State<ChildSafetyListScreen> createState() => _ChildSafetyListScreenState();
}

class _ChildSafetyListScreenState extends State<ChildSafetyListScreen> {
  final ChildSafetyRepository _repository = ChildSafetyRepository();

  List<ChildProfileModel> profiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final list = await _repository.getProfiles();
    if (!mounted) return;
    setState(() {
      profiles = list;
      _loading = false;
    });
  }

  Future<void> _deleteProfile(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Profile"),
        content: Text("Remove child profile for $name?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.emergency),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _repository.deleteProfile(id);
    await _loadProfiles();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile removed successfully.')),
    );
  }

  Future<void> _openAddProfile() async {
    await context.push('/child-safety/add');
    await _loadProfiles();
  }

  Future<void> _openEditProfile(ChildProfileModel profile) async {
    await context.push('/child-safety/edit', extra: profile);
    await _loadProfiles();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgApp : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Child Safety Profiles'),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddProfile,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Profile'),
        backgroundColor: isDark ? AppColors.accent : AppColors.primary,
        foregroundColor: isDark ? AppColors.bgApp : Colors.white,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : profiles.isEmpty
                ? SetuEmptyState(
                    icon: Icons.child_care_rounded,
                    title: 'No Profiles Registered',
                    description:
                        'Store child medical requirements, guardian details, and safe zone coordinates for rapid off-grid broadcasts.',
                    actionLabel: 'Register Child Profile',
                    onAction: _openAddProfile,
                  )
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      SetuCard(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        backgroundColor: isDark ? AppColors.bgSurfaceAlt : AppColors.lightSurface,
                        accentBorderLeft: AppColors.accent,
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.14),
                                borderRadius: AppRadius.smRadius,
                              ),
                              child: const Icon(Icons.shield_outlined, color: AppColors.accent, size: 20),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Guardian Rapid Response',
                                    style: AppTypography.cardTitle.copyWith(
                                      color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Profiles can be immediately attached to lost-child broadcasts across the mesh network.',
                                    style: AppTypography.caption.copyWith(
                                      color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: AppSpacing.lg),

                      const SetuSectionHeader(
                        title: 'Saved Profiles',
                        subtitle: 'Tap to view or edit details',
                        padding: EdgeInsets.only(bottom: AppSpacing.sm),
                      ),

                      ...profiles.map(
                        (profile) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: SetuCard(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            onTap: () => _openEditProfile(profile),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isDark ? AppColors.bgInput : AppColors.lightBackground,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isDark ? AppColors.borderSubtle : AppColors.lightBorder,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.child_care_rounded,
                                    size: 22,
                                    color: AppColors.accent,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        profile.childName,
                                        style: AppTypography.cardTitle.copyWith(
                                          color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                                          fontSize: 14.5,
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        'Age ${profile.childAge} · Guardian: ${profile.guardianName}',
                                        style: AppTypography.caption.copyWith(
                                          color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: AppColors.emergency,
                                    size: 20,
                                  ),
                                  tooltip: 'Delete Profile',
                                  onPressed: () => _deleteProfile(profile.id, profile.childName),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 80),
                    ],
                  ),
      ),
    );
  }
}
