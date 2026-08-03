// =====================================================
// SETU Project
// Module : Language Selection (Block 30)
// Owner  : Sudheer
// =====================================================
//
// HONEST SCOPE NOTE: this screen genuinely saves the choice
// and reflects it back correctly — but actual app-wide string
// translation isn't wired yet. That needs the `intl` package +
// generated ARB files for every string in the app, which is a
// larger, separate piece of work. Selecting a language here
// doesn't yet retranslate the UI — flagging that honestly
// rather than faking it silently.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/features/settings/data/repositories/settings_repository.dart';

class _LanguageOption {
  final String code;
  final String nativeLabel;
  final String englishLabel;

  const _LanguageOption(this.code, this.nativeLabel, this.englishLabel);
}

const _languages = [
  _LanguageOption('en', 'English', 'English'),
  _LanguageOption('hi', 'हिन्दी', 'Hindi'),
  _LanguageOption('bn', 'বাংলা', 'Bengali'),
  _LanguageOption('ta', 'தமிழ்', 'Tamil'),
  _LanguageOption('te', 'తెలుగు', 'Telugu'),
  _LanguageOption('mr', 'मराठी', 'Marathi'),
  _LanguageOption('gu', 'ગુજરાતી', 'Gujarati'),
  _LanguageOption('kn', 'ಕನ್ನಡ', 'Kannada'),
  _LanguageOption('ml', 'മലയാളം', 'Malayalam'),
  _LanguageOption('pa', 'ਪੰਜਾਬੀ', 'Punjabi'),
  _LanguageOption('ur', 'اردو', 'Urdu'),
];

class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({super.key});

  @override
  State<LanguageSelectionScreen> createState() =>
      _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  final SettingsRepository _settingsRepository = SettingsRepository();
  String _selected = 'en';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _settingsRepository.getSettings();
    if (!mounted) return;
    setState(() {
      _selected = settings.languageCode;
      _loading = false;
    });
  }

  Future<void> _select(String code) async {
    setState(() => _selected = code);

    final settings = await _settingsRepository.getSettings();
    await _settingsRepository.saveSettings(
      settings.copyWith(languageCode: code),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Select Language')),
      body: RadioGroup<String>(
        groupValue: _selected,
        onChanged: (value) {
          if (value != null) _select(value);
        },
        child: GridView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 2.4,
        ),
        itemCount: _languages.length,
        itemBuilder: (context, index) {
          final lang = _languages[index];
          final isSelected = lang.code == _selected;

          return InkWell(
            borderRadius: AppRadius.mdRadius,
            onTap: () => _select(lang.code),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primaryContainer
                    : Theme.of(context).cardColor,
                borderRadius: AppRadius.mdRadius,
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : Theme.of(context).dividerColor,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Radio<String>(value: lang.code),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(lang.nativeLabel, style: AppTypography.subtitle),
                        Text(
                          lang.englishLabel,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.neutral500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: () => context.pop(),
              child: const Text('Continue'),
            ),
          ),
        ),
      ),
    );
  }
}
