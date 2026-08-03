import 'package:go_router/go_router.dart';

import 'package:setu_app/features/home/presentation/screens/home_screen.dart';
import 'package:setu_app/features/stealth/presentation/screens/stealth_screen.dart';
import 'package:setu_app/features/confirmation/presentation/screens/confirmation_screen.dart';
import 'package:setu_app/features/contacts/presentation/screens/contacts_screen.dart';
import 'package:setu_app/features/contacts/presentation/screens/add_contact_screen.dart';
import 'package:setu_app/features/location/presentation/screens/location_test_screen.dart';
import 'package:setu_app/features/history/presentation/screens/history_screen.dart';
import 'package:setu_app/features/settings/screens/settings_screen.dart';
import 'package:setu_app/features/settings/data/repositories/settings_repository.dart';
import 'package:setu_app/features/nearby/presentation/screens/nearby_screen.dart';
import 'package:setu_app/features/community/presentation/screens/community_demo_screen.dart';
import 'package:setu_app/features/child_safety/data/models/child_profile_model.dart';
import 'package:setu_app/features/child_safety/presentation/screens/child_safety_list_screen.dart';
import 'package:setu_app/features/child_safety/presentation/screens/add_child_profile_screen.dart';
import 'package:setu_app/features/lost_child/presentation/screens/lost_child_demo_screen.dart';
import 'package:setu_app/features/lost_child/presentation/screens/lost_child_broadcast_screen.dart';
import 'package:setu_app/features/auth/presentation/screens/login_screen.dart';
import 'package:setu_app/features/auth/presentation/screens/otp_screen.dart';
import 'package:setu_app/features/onboarding/presentation/screens/permission_gate_screen.dart';
import 'package:setu_app/features/profile/presentation/screens/complete_profile_screen.dart';
import 'package:setu_app/features/language/presentation/screens/language_selection_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      // Block 31: checks login (name+phone via OTP) before the
      // Block 25 stealth-mode check. A brand-new install should
      // always hit Login first.
      redirect: (context, state) async {
        final settings = await SettingsRepository().getSettings();

        if (settings.userName.isEmpty || settings.phoneNumber.isEmpty) {
          return '/login';
        }

        // Added Aug 4 2026: mesh (BLE/Wi-Fi/nearby/location) permissions
        // are checked once, right after login, before any home/stealth
        // redirect -- a device without these can't relay for anyone,
        // which defeats the whole point of the app being installed.
        // hasMeshPermissions() is cheap (just reads cached OS permission
        // status, no dialogs), so this check is safe to run on every
        // redirect, not just first launch.
        if (!await hasMeshPermissions()) {
          return '/permissions';
        }

        if (settings.stealthMode) {
          return '/stealth';
        }

        return null;
      },
      builder: (context, state) => const HomeScreen(),
    ),

    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),

    GoRoute(
      path: '/permissions',
      builder: (context, state) => const PermissionGateScreen(),
    ),

    GoRoute(
      path: '/otp',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return OtpScreen(
          name: extra['name'] as String,
          phone: extra['phone'] as String,
          otp: extra['otp'] as String,
        );
      },
    ),

    GoRoute(
      path: '/complete-profile',
      builder: (context, state) => const CompleteProfileScreen(),
    ),

    GoRoute(
      path: '/language',
      builder: (context, state) => const LanguageSelectionScreen(),
    ),

    GoRoute(
      path: '/stealth',
      builder: (context, state) => const StealthScreen(),
    ),

    GoRoute(
      path: '/confirmation',
      builder: (context, state) => const ConfirmationScreen(),
    ),

    GoRoute(
      path: '/contacts',
      builder: (context, state) => const ContactsScreen(),
    ),

    GoRoute(
      path: '/add-contact',
      builder: (context, state) => const AddContactScreen(),
    ),

    GoRoute(
      path: '/location-test',
      builder: (context, state) => const LocationTestScreen(),
    ),

    GoRoute(
      path: '/history',
      builder: (context, state) => const HistoryScreen(),
    ),

    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),

    GoRoute(path: '/nearby', builder: (context, state) => const NearbyScreen()),

    GoRoute(
      path: '/community-demo',
      builder: (context, state) => const CommunityDemoScreen(),
    ),

    GoRoute(
      path: '/child-safety',
      builder: (context, state) => const ChildSafetyListScreen(),
    ),
    GoRoute(
      path: '/child-safety/add',
      builder: (context, state) => const AddChildProfileScreen(),
    ),
    GoRoute(
      path: '/child-safety/edit',
      builder: (context, state) => AddChildProfileScreen(
        existingProfile: state.extra as ChildProfileModel?,
      ),
    ),

    GoRoute(
      path: '/lost-child',
      builder: (context, state) => const LostChildDemoScreen(),
    ),
    GoRoute(
      path: '/lost-child/broadcast',
      builder: (context, state) => const LostChildBroadcastScreen(),
    ),
  ],
);
