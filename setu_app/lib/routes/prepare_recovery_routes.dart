import 'package:go_router/go_router.dart';

import 'package:setu_app/features/preparedness/data/repositories/checklist_repository.dart';
import 'package:setu_app/features/preparedness/presentation/screens/checklist_screen.dart';
import 'package:setu_app/features/preparedness/presentation/screens/checklists_screen.dart';
import 'package:setu_app/features/preparedness/presentation/screens/disaster_guides_screen.dart';
import 'package:setu_app/features/preparedness/presentation/screens/emergency_contacts_screen.dart';
import 'package:setu_app/features/preparedness/presentation/screens/emergency_plan_screen.dart';
import 'package:setu_app/features/preparedness/presentation/screens/preparedness_screen.dart';
import 'package:setu_app/features/preparedness/presentation/screens/readiness_check_screen.dart';
import 'package:setu_app/features/preparedness/presentation/screens/safety_guide_detail_screen.dart';
import 'package:setu_app/features/recovery/data/services/recovery_guidance_service.dart';
import 'package:setu_app/features/recovery/presentation/screens/damage_report_screen.dart';
import 'package:setu_app/features/recovery/presentation/screens/missing_person_screen.dart';
import 'package:setu_app/features/recovery/presentation/screens/my_reports_screen.dart';
import 'package:setu_app/features/recovery/presentation/screens/recovery_guidance_screen.dart';
import 'package:setu_app/features/recovery/presentation/screens/recovery_screen.dart';
import 'package:setu_app/features/recovery/presentation/screens/report_detail_screen.dart';
import 'package:setu_app/features/recovery/presentation/screens/resource_request_screen.dart';

/// Prepare (before-disaster) routes. Kept in their own file so the
/// navigation can be exercised in tests with the real route table.
///
///   /preparedness                Prepare Home
///     /guides  /guide/:id        Disaster guides
///     /kit                       Emergency kit
///     /checklists  /checklists/:id
///     /plan                      Emergency plan
///     /contacts                  Emergency contacts
///     /readiness                 Device readiness check
List<RouteBase> preparednessRoutes() => [
      GoRoute(
        path: '/preparedness',
        builder: (context, state) => const PreparednessScreen(),
      ),
      GoRoute(
        path: '/preparedness/guides',
        builder: (context, state) => const DisasterGuidesScreen(),
      ),
      GoRoute(
        path: '/preparedness/guide/:id',
        builder: (context, state) =>
            SafetyGuideDetailScreen(guideId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/preparedness/kit',
        builder: (context, state) =>
            const ChecklistScreen(checklistId: ChecklistRepository.kitId),
      ),
      GoRoute(
        path: '/preparedness/checklists',
        builder: (context, state) => const ChecklistsScreen(),
      ),
      GoRoute(
        path: '/preparedness/checklists/:id',
        builder: (context, state) =>
            ChecklistScreen(checklistId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/preparedness/plan',
        builder: (context, state) => const EmergencyPlanScreen(),
      ),
      GoRoute(
        path: '/preparedness/contacts',
        builder: (context, state) => const EmergencyContactsScreen(),
      ),
      GoRoute(
        path: '/preparedness/readiness',
        builder: (context, state) => const ReadinessCheckScreen(),
      ),
    ];

/// Recovery (after-disaster) routes. Report forms take an optional
/// `?draft=<id>` to resume a draft or edit a failed report.
///
///   /recovery                    Recovery Home
///     /damage  /missing  /request        Report forms
///     /guidance  /guidance/:id           Recovery guidance
///     /reports  /reports/:id             My reports
List<RouteBase> recoveryRoutes() => [
      GoRoute(
        path: '/recovery',
        builder: (context, state) => const RecoveryScreen(),
      ),
      GoRoute(
        path: '/recovery/damage',
        builder: (context, state) =>
            DamageReportScreen(draftId: state.uri.queryParameters['draft']),
      ),
      GoRoute(
        path: '/recovery/missing',
        builder: (context, state) =>
            MissingPersonScreen(draftId: state.uri.queryParameters['draft']),
      ),
      GoRoute(
        path: '/recovery/request',
        builder: (context, state) =>
            ResourceRequestScreen(draftId: state.uri.queryParameters['draft']),
      ),
      GoRoute(
        path: '/recovery/guidance',
        builder: (context, state) => const RecoveryGuidanceScreen(),
      ),
      GoRoute(
        path: '/recovery/guidance/:id',
        builder: (context, state) => SafetyGuideDetailScreen(
          guideId: state.pathParameters['id']!,
          library: RecoveryGuidanceService.instance,
        ),
      ),
      GoRoute(
        path: '/recovery/reports',
        builder: (context, state) => const MyReportsScreen(),
      ),
      GoRoute(
        path: '/recovery/reports/:id',
        builder: (context, state) =>
            ReportDetailScreen(reportId: state.pathParameters['id']!),
      ),
    ];
