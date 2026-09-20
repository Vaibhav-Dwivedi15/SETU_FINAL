import 'package:flutter/material.dart';

import 'core/design_system/app_theme.dart';
import 'core/language/language_controller.dart';
import 'core/services/volume_button_sos_service.dart';
import 'core/theme/theme_controller.dart';
import 'routes/app_router.dart';

/// Block 31: global key so services outside the widget tree
/// (like VolumeButtonSosService) can show SnackBars without
/// needing a BuildContext passed in.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

class SetuSOSApp extends StatefulWidget {
  const SetuSOSApp({super.key});

  @override
  State<SetuSOSApp> createState() => _SetuSOSAppState();
}

class _SetuSOSAppState extends State<SetuSOSApp> {
  @override
  void initState() {
    super.initState();
    ThemeController.instance.loadSavedTheme();
    // Loads the persisted language choice (if any) so AppStrings.of()
    // returns the right table from first frame, not just after the
    // Language screen is visited again. Mirrors ThemeController's own
    // loadSavedTheme() call directly above it.
    LanguageController.instance.loadSavedLanguage();
    VolumeButtonSosService.instance.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        // Nested ListenableBuilder rather than merging both controllers
        // into one: keeps ThemeController and LanguageController fully
        // independent (a language change doesn't need to know theme
        // exists, or vice versa), same separation of concerns the
        // project already applies to its other single-purpose
        // ChangeNotifiers.
        return ListenableBuilder(
          listenable: LanguageController.instance,
          builder: (context, __) {
            return MaterialApp.router(
              title: 'SETU SOS',
              debugShowCheckedModeBanner: false,
              routerConfig: appRouter,
              theme: AppDesignSystem.lightTheme,
              darkTheme: AppDesignSystem.darkTheme,
              themeMode: ThemeController.instance.themeMode,
              scaffoldMessengerKey: rootScaffoldMessengerKey,
            );
          },
        );
      },
    );
  }
}
