import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          color: Colors.grey,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Settings"), centerTitle: true),
      body: ListView(
        children: [
          _sectionHeader("PROFILE"),

          ListTile(
            leading: const Icon(Icons.person),
            title: Text(
              _settings!.userName.isNotEmpty
                  ? _settings!.userName
                  : "Not set",
            ),
            subtitle: Text(
              _settings!.phoneNumber.isNotEmpty
                  ? "+91 ${_settings!.phoneNumber}"
                  : "No phone on file",
            ),
            trailing: const Icon(Icons.edit, size: 18),
            onTap: () async {
              final nameController = TextEditingController(
                text: _settings!.userName,
              );

              final saved = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Edit Name"),
                  content: TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: "Name"),
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

          ListTile(
            leading: const Icon(Icons.medical_information_outlined),
            title: const Text("Complete Your Profile"),
            subtitle: Text(
              _settings!.bloodGroup.isNotEmpty
                  ? "Blood group: ${_settings!.bloodGroup}"
                  : "Blood group, medical note — optional",
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/complete-profile'),
          ),

          ListTile(
            leading: const Icon(Icons.language),
            title: const Text("Language"),
            subtitle: const Text("English (translation coming soon)"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/language'),
          ),

          const Divider(),

          _sectionHeader("APPEARANCE"),

          ListenableBuilder(
            listenable: ThemeController.instance,
            builder: (context, _) {
              return RadioGroup<ThemeMode>(
                groupValue: ThemeController.instance.themeMode,
                onChanged: (value) {
                  if (value != null) {
                    ThemeController.instance.setThemeMode(value);
                  }
                },
                child: Column(
                  children: ThemeMode.values.map((mode) {
                    return RadioListTile<ThemeMode>(
                      value: mode,
                      title: Text(_themeModeLabel(mode)),
                      secondary: Icon(
                        mode == ThemeMode.dark
                            ? Icons.dark_mode
                            : mode == ThemeMode.light
                                ? Icons.light_mode
                                : Icons.brightness_auto,
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),

          const Divider(),

          _sectionHeader("SOS TRIGGER STYLE"),

          RadioGroup<String>(
            groupValue: _settings!.sosTriggerMode,
            onChanged: (value) async {
              if (value == null) return;
              setState(() {
                _settings = _settings!.copyWith(sosTriggerMode: value);
              });
              await _saveSettings();
            },
            child: Column(
              children: [
                RadioListTile<String>(
                  value: 'tap',
                  title: const Text("Tap & Wait"),
                  subtitle: const Text(
                    "Single tap, then cancel during the countdown below",
                  ),
                  secondary: const Icon(Icons.touch_app),
                ),
                RadioListTile<String>(
                  value: 'hold',
                  title: const Text("Hold to Confirm"),
                  subtitle: const Text(
                    "Press and hold the SOS button for 3 seconds",
                  ),
                  secondary: const Icon(Icons.fingerprint),
                ),
              ],
            ),
          ),

          const Divider(),

          _sectionHeader("EMERGENCY BEHAVIOR"),

          ListTile(
            leading: const Icon(Icons.timer),
            title: const Text("SOS Countdown"),
            subtitle: const Text(
              "Wait time before SOS sends (Tap & Wait, or after Hold)",
            ),
            trailing: DropdownButton<int>(
              value: _settings!.sosCountdown,
              items: const [
                DropdownMenuItem(value: 3, child: Text("3 sec")),
                DropdownMenuItem(value: 5, child: Text("5 sec")),
                DropdownMenuItem(value: 10, child: Text("10 sec")),
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

          SwitchListTile(
            value: _settings!.autoRetry,
            secondary: const Icon(Icons.sms),
            title: const Text("Auto Retry SMS"),
            onChanged: (value) async {
              setState(() {
                _settings = _settings!.copyWith(autoRetry: value);
              });

              await _saveSettings();
            },
          ),

          SwitchListTile(
            value: _settings!.highAccuracyLocation,
            secondary: const Icon(Icons.location_on),
            title: const Text("High Accuracy GPS"),
            onChanged: (value) async {
              setState(() {
                _settings = _settings!.copyWith(highAccuracyLocation: value);
              });

              await _saveSettings();
            },
          ),

          SwitchListTile(
            value: _settings!.stealthMode,
            secondary: const Icon(Icons.visibility_off),
            title: const Text("Stealth Mode"),
            onChanged: (value) async {
              setState(() {
                _settings = _settings!.copyWith(stealthMode: value);
              });

              await _saveSettings();
            },
          ),
          SwitchListTile(
            value: _settings!.relayEnabled,
            secondary: const Icon(Icons.bluetooth),
            title: const Text("Relay Mode"),
            onChanged: (value) async {
              setState(() {
                _settings = _settings!.copyWith(relayEnabled: value);
              });

              await _saveSettings();
            },
          ),

          const SizedBox(height: 30),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: FilledButton.icon(
              icon: const Icon(Icons.restore),
              label: const Text("Restore Default Settings"),
              onPressed: () {
                _restoreDefaults().then((_) {
                  if (!mounted) return;

                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(
                      content: Text("Settings restored successfully"),
                    ),
                  );
                });
              },
            ),
          ),

          const Divider(height: 40),

          _sectionHeader("DIAGNOSTICS"),

          ListTile(
            leading: const Icon(Icons.location_on),
            title: const Text("Test GPS Location"),
            subtitle: const Text("Check that location permission and accuracy work"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/location-test'),
          ),

          const SizedBox(height: 24),

          const Center(
            child: Text(
              "SETU SOS v1.0",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
            ),
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
