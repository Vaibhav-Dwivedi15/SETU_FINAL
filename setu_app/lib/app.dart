import 'package:flutter/material.dart';

import 'core/design_system/app_theme.dart';
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
    VolumeButtonSosService.instance.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
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
  }
}
