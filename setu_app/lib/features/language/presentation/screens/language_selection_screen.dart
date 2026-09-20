// =====================================================
// SETU Project
// Module : Language Selection (Block 30)
// Owner  : Sudheer
// =====================================================
//
// UPDATE: app-wide translation is now wired for 6 of the 11 languages
// listed below -- see core/language/app_strings.dart + LanguageController.
// Selecting one of {English, Hindi, Bengali, Tamil, Telugu, Marathi} now
// genuinely retranslates the screens that have been migrated to
// AppStrings.of(context).t(...) (login, OTP, voice SOS, and a handful of
// home-screen strings as a first pass -- see app_strings.dart's own
// coverage note for exactly what's done vs not yet).
//
// The remaining 5 languages (Gujarati, Kannada, Malayalam, Punjabi, Urdu)
// are still selectable and saved correctly, but have no string table yet
// -- they fall back to English rather than showing untranslated gaps or
// blank text. That fallback is intentional, not a bug: extending real
// coverage to them just means adding their key/value maps to
// app_strings.dart, no architecture change needed.
//
// The rest of the app (every screen not yet migrated to AppStrings) is
// still hardcoded English regardless of this setting -- that remains
// honestly true and is NOT fixed by this change. See app_strings.dart.
//
// Aug 4 2026 dark-mode fix: nativeLabel used AppTypography.subtitle
// with no explicit color, so it inherited the theme's default text
// color. On a selected card, the background is the FIXED light
// primaryContainer -- theme-driven light text (dark mode) on a fixed
// light background was invisible. englishLabel below it was already
// fine (fixed neutral500 color). Fix: explicit AppColors.primary text
// only when selected; unselected cards keep the normal theme-inherited
// color (null falls through), since that case was never broken.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/language/language_controller.dart';
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

    // This is the line that actually makes the choice take effect --
    // previously the code above was the ONLY thing that happened here,
    // which is why the old header note said selection didn't retranslate
    // anything. LanguageController.setLanguage() notifies the
    // ListenableBuilder in app.dart, which rebuilds the whole app --
    // any screen reading AppStrings.of(context) updates immediately.
    await LanguageController.instance.setLanguage(code);
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
                        Text(
                          lang.nativeLabel,
                          style: AppTypography.subtitle.copyWith(
                            color: isSelected ? AppColors.primary : null,
                          ),
                        ),
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
