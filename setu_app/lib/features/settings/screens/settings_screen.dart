// =====================================================
// SETU Project
// Module : Settings Screen (Redesign)
// =====================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';
import 'package:setu_app/core/theme/theme_controller.dart';

import '../data/models/settings_model.dart';
import '../data/repositories/settings_repository.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsRepository _repository = SettingsRepository();

  SettingsModel? _settings;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _repository.getSettings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _loading = false;
    });
  }

  Future<void> _saveSettings() async {
    if (_settings == null) return;
    await _repository.saveSettings(_settings!);
  }

  Future<void> _restoreDefaults() async {
    await _repository.resetSettings();
    final settings = await _repository.getSettings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
    });
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'System Default';
      case ThemeMode.light:
        return 'Light Theme';
      case ThemeMode.dark:
        return 'Dark Theme (Graphite)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading || _settings == null) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.bgApp : AppColors.lightBackground,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgApp : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text("Settings & Preferences"),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          children: [
            // PROFILE SECTION
            const SetuSectionHeader(
              title: "User Profile",
              subtitle: "Emergency responder identifier",
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
            ),
            SetuCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.person_outline_rounded, color: AppColors.accent),
                    title: Text(
                      _settings!.userName.isNotEmpty ? _settings!.userName : "Citizen Name Not Set",
                      style: AppTypography.cardTitle,
                    ),
                    subtitle: Text(
                      _settings!.phoneNumber.isNotEmpty
                          ? "+91 ${_settings!.phoneNumber}"
                          : "No phone registered",
                      style: AppTypography.caption.copyWith(
                        color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                    trailing: const Icon(Icons.edit_outlined, size: 18),
                    onTap: () async {
                      final nameController = TextEditingController(
                        text: _settings!.userName,
                      );
                      final saved = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text("Edit Citizen Name"),
                          content: TextField(
                            controller: nameController,
                            decoration: const InputDecoration(labelText: "Full Name"),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text("Cancel"),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text("Save"),
                            ),
                          ],
                        ),
                      );

                      if (saved == true) {
                        setState(() {
                          _settings = _settings!.copyWith(
                            userName: nameController.text.trim(),
                          );
                        });
                        await _saveSettings();
                      }
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.medical_information_outlined, color: AppColors.accent),
                    title: const Text("Medical & Emergency Info", style: AppTypography.cardTitle),
                    subtitle: Text(
                      _settings!.bloodGroup.isNotEmpty
                          ? "Blood group: ${_settings!.bloodGroup}"
                          : "Blood group, allergies, medications",
                      style: AppTypography.caption.copyWith(
                        color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                    onTap: () => context.push('/complete-profile'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.language_rounded, color: AppColors.accent),
                    title: const Text("Language Selection", style: AppTypography.cardTitle),
                    subtitle: Text(
                      "Multi-language offline translations",
                      style: AppTypography.caption.copyWith(
                        color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                    onTap: () => context.push('/language'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // APPEARANCE SECTION
            const SetuSectionHeader(
              title: "Appearance",
              subtitle: "Theme visual console",
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
            ),
            SetuCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ListenableBuilder(
                listenable: ThemeController.instance,
                builder: (context, _) {
                  return Column(
                    children: ThemeMode.values.map((mode) {
                      // ignore: deprecated_member_use
                      return RadioListTile<ThemeMode>(
                        value: mode,
                        groupValue: ThemeController.instance.themeMode,
                        title: Text(_themeModeLabel(mode), style: AppTypography.bodyStrong),
                        secondary: Icon(
                          mode == ThemeMode.dark
                              ? Icons.dark_mode_outlined
                              : mode == ThemeMode.light
                                  ? Icons.light_mode_outlined
                                  : Icons.brightness_auto_outlined,
                          color: AppColors.accent,
                        ),
                        onChanged: (value) {
                          if (value != null) {
                            ThemeController.instance.setThemeMode(value);
                          }
                        },
                      );
                    }).toList(),
                  );
                },
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // SOS TRIGGER STYLE
            const SetuSectionHeader(
              title: "SOS Activation Gesture",
              subtitle: "Prevents accidental distress alerts",
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
            ),
            SetuCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  // ignore: deprecated_member_use
                  RadioListTile<String>(
                    value: 'tap',
                    groupValue: _settings!.sosTriggerMode,
                    title: const Text("Tap & Countdown", style: AppTypography.bodyStrong),
                    subtitle: const Text("Single tap followed by safety countdown cancel window"),
                    secondary: const Icon(Icons.touch_app_rounded, color: AppColors.accent),
                    onChanged: (value) async {
                      if (value == null) return;
                      setState(() {
                        _settings = _settings!.copyWith(sosTriggerMode: value);
                      });
                      await _saveSettings();
                    },
                  ),
                  const Divider(height: 1),
                  // ignore: deprecated_member_use
                  RadioListTile<String>(
                    value: 'hold',
                    groupValue: _settings!.sosTriggerMode,
                    title: const Text("Hold to Confirm (3 Seconds)", style: AppTypography.bodyStrong),
                    subtitle: const Text("Continuous press-and-hold prevents pocket triggers"),
                    secondary: const Icon(Icons.fingerprint_rounded, color: AppColors.accent),
                    onChanged: (value) async {
                      if (value == null) return;
                      setState(() {
                        _settings = _settings!.copyWith(sosTriggerMode: value);
                      });
                      await _saveSettings();
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // EMERGENCY BEHAVIOR
            const SetuSectionHeader(
              title: "Emergency Network Controls",
              subtitle: "Radio transmission parameters",
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
            ),
            SetuCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.timer_outlined, color: AppColors.accent),
                    title: const Text("Countdown Buffer", style: AppTypography.cardTitle),
                    subtitle: const Text("Grace period before beacon dispatches"),
                    trailing: DropdownButton<int>(
                      value: _settings!.sosCountdown,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 3, child: Text("3s")),
                        DropdownMenuItem(value: 5, child: Text("5s")),
                        DropdownMenuItem(value: 10, child: Text("10s")),
                      ],
                      onChanged: (value) async {
                        if (value == null) return;
                        setState(() {
                          _settings = _settings!.copyWith(sosCountdown: value);
                        });
                        await _saveSettings();
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    value: _settings!.autoRetry,
                    secondary: const Icon(Icons.sms_outlined, color: AppColors.accent),
                    title: const Text("Auto-Retry SMS Dispatch", style: AppTypography.cardTitle),
                    subtitle: const Text("Attempts direct cellular SMS queue if available"),
                    onChanged: (value) async {
                      setState(() {
                        _settings = _settings!.copyWith(autoRetry: value);
                      });
                      await _saveSettings();
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    value: _settings!.highAccuracyLocation,
                    secondary: const Icon(Icons.gps_fixed_rounded, color: AppColors.accent),
                    title: const Text("High Accuracy GPS", style: AppTypography.cardTitle),
                    subtitle: const Text("Uses multi-satellite positioning for pin-point rescue"),
                    onChanged: (value) async {
                      setState(() {
                        _settings = _settings!.copyWith(highAccuracyLocation: value);
                      });
                      await _saveSettings();
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    value: _settings!.stealthMode,
                    secondary: const Icon(Icons.visibility_off_outlined, color: AppColors.warning),
                    title: const Text("Calculator Stealth Mode", style: AppTypography.cardTitle),
                    subtitle: const Text("Disguises app as calculator on launch"),
                    onChanged: (value) async {
                      setState(() {
                        _settings = _settings!.copyWith(stealthMode: value);
                      });
                      await _saveSettings();
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    value: _settings!.relayEnabled,
                    secondary: const Icon(Icons.hub_rounded, color: AppColors.relay),
                    title: const Text("Citizen Relay Mode", style: AppTypography.cardTitle),
                    subtitle: const Text("Carries encrypted emergency packets for neighbors"),
                    onChanged: (value) async {
                      setState(() {
                        _settings = _settings!.copyWith(relayEnabled: value);
                      });
                      await _saveSettings();
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // DIAGNOSTICS & SYSTEM
            const SetuSectionHeader(
              title: "Diagnostics & Radio Testing",
              subtitle: "Hardware status checks",
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
            ),
            SetuCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.my_location_rounded, color: AppColors.accent),
                    title: const Text("Test GPS Sensor", style: AppTypography.cardTitle),
                    subtitle: const Text("Verify satellite fix speed and accuracy"),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                    onTap: () => context.push('/location-test'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.wifi_tethering_rounded, color: AppColors.relay),
                    title: const Text("Relay Mesh Diagnostics", style: AppTypography.cardTitle),
                    subtitle: const Text("Inspect hop statistics and packet delivery metrics"),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                    onTap: () => context.push('/relay'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            SetuButton(
              label: "RESTORE DEFAULT SETTINGS",
              icon: Icons.restore_rounded,
              onPressed: () async {
                await _restoreDefaults();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Settings restored to factory defaults"),
                  ),
                );
              },
              variant: SetuButtonVariant.outlined,
              size: SetuButtonSize.md,
            ),

            const SizedBox(height: AppSpacing.xl),

            Center(
              child: Column(
                children: [
                  Text(
                    "SETU EMERGENCY PLATFORM",
                    style: AppTypography.metadata.copyWith(
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.textDim : AppColors.lightTextDim,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Production Build v2.0 (Offline Mesh First)",
                    style: AppTypography.caption.copyWith(
                      color: isDark ? AppColors.textDim : AppColors.lightTextDim,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}
