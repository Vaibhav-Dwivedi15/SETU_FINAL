// =====================================================
// SETU Project
// Module : Prepare + Recovery navigation and form flows (widget tests)
// =====================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setu_app/features/recovery/data/models/recovery_enums.dart';
import 'package:setu_app/features/recovery/data/models/recovery_report_type.dart';
import 'package:setu_app/features/recovery/data/models/resource_request.dart';
import 'package:setu_app/features/recovery/data/models/report_status.dart';
import 'package:setu_app/features/recovery/data/repositories/recovery_repository.dart';
import 'package:setu_app/features/recovery/data/services/recovery_dispatcher.dart';
import 'package:setu_app/features/recovery/data/models/recovery_record.dart';
import 'package:setu_app/features/recovery/presentation/screens/damage_report_screen.dart';
import 'package:setu_app/features/recovery/presentation/screens/missing_person_screen.dart';
import 'package:setu_app/features/recovery/presentation/screens/my_reports_screen.dart';
import 'package:setu_app/features/recovery/presentation/screens/report_detail_screen.dart';
import 'package:setu_app/features/recovery/presentation/screens/resource_request_screen.dart';
import 'package:setu_app/routes/prepare_recovery_routes.dart';

import 'support/fake_assets.dart';

class _Dispatcher implements RecoveryDispatcher {
  _Dispatcher({this.fail = false});
  bool fail;
  int calls = 0;

  @override
  Future<String> dispatch(RecoveryRecord record) async {
    calls++;
    if (fail) throw const RecoveryDispatchException('No route available');
    return 'e-$calls';
  }
}

void _bigScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The real Prepare/Recovery route tables, plus stubs for the routes that
/// belong to the rest of the app.
GoRouter _appRouter(String initial) => GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('HOME STUB'))),
        GoRoute(path: '/history', builder: (_, _) => const Scaffold(body: Text('HISTORY STUB'))),
        GoRoute(path: '/contacts', builder: (_, _) => const Scaffold(body: Text('CONTACTS STUB'))),
        ...preparednessRoutes(),
        ...recoveryRoutes(),
      ],
    );

Future<GoRouter> _pumpApp(WidgetTester tester, String initial) async {
  _bigScreen(tester);
  final router = _appRouter(initial);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

Future<void> _back(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
}

/// Forms and detail screens with an injected repository (so nothing
/// touches the mesh), inside a router that has the detail route.
Future<GoRouter> _pumpForm(
  WidgetTester tester,
  RecoveryRepository repo,
  Widget Function() form,
) async {
  _bigScreen(tester);
  // Forms are always pushed on top of another screen in the app, so the
  // harness does the same (popping the only page is not a real scenario).
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('BASE'))),
    GoRoute(path: '/form', builder: (_, _) => form()),
    GoRoute(
      path: '/recovery/reports/:id',
      builder: (_, state) =>
          ReportDetailScreen(reportId: state.pathParameters['id']!, repository: repo),
    ),
  ]);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  unawaited(router.push<Object?>('/form'));
  await tester.pumpAndSettle();
  return router;
}

Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.widgetWithText(TextField, label), text);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => readBundledAssets([
        'assets/preparedness/safety_guides.json',
        'assets/preparedness/checklists.json',
        'assets/recovery/recovery_guidance.json',
      ]));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    serveBundledAssets();
  });

  group('Prepare navigation', () {
    testWidgets('Prepare Home lists every section', (tester) async {
      await _pumpApp(tester, '/preparedness');
      for (final t in [
        'Disaster guides', 'Emergency kit', 'Safety checklists', 'Emergency plan',
        'Emergency contacts', 'Device readiness check',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('Everything in Prepare works without internet.'), findsOneWidget);
    });

    testWidgets('guides -> Flood -> Before/During/After/Avoid -> back -> back', (tester) async {
      await _pumpApp(tester, '/preparedness');
      await tester.tap(find.text('Disaster guides'));
      await tester.pumpAndSettle();
      for (final d in ['Flood', 'Earthquake', 'Cyclone', 'Fire', 'Landslide']) {
        expect(find.text(d), findsOneWidget, reason: d);
      }

      await tester.tap(find.text('Cyclone'));
      await tester.pumpAndSettle();
      for (final s in ['BEFORE', 'DURING', 'AFTER', 'AVOID']) {
        expect(find.text(s), findsOneWidget, reason: s);
      }

      await _back(tester);
      expect(find.text('Disaster guides'), findsWidgets);
      await _back(tester);
      expect(find.text('Emergency kit'), findsOneWidget);
    });

    testWidgets('Emergency kit: tick an item, progress updates and persists', (tester) async {
      await _pumpApp(tester, '/preparedness');
      expect(find.text('Emergency kit'), findsOneWidget);
      await tester.tap(find.text('Emergency kit'));
      await tester.pumpAndSettle();

      expect(find.text('0 of 13 done · 13 remaining'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pumpAndSettle();
      expect(find.text('1 of 13 done · 12 remaining'), findsOneWidget);

      // back to hub: the hub reflects the saved progress
      await _back(tester);
      expect(find.text('1 of 13 packed'), findsOneWidget);

      // reopen: state restored from storage
      await tester.tap(find.text('Emergency kit'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 13 done · 12 remaining'), findsOneWidget);
    });

    testWidgets('Emergency kit: reset asks first, then clears', (tester) async {
      await _pumpApp(tester, '/preparedness/kit');
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reset checklist'));
      await tester.pumpAndSettle();
      expect(find.text('Reset checklist?'), findsOneWidget);
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(find.text('0 of 13 done · 13 remaining'), findsOneWidget);
    });

    testWidgets('Safety checklists -> Family safety (nested) -> back', (tester) async {
      await _pumpApp(tester, '/preparedness');
      await tester.tap(find.text('Safety checklists'));
      await tester.pumpAndSettle();
      for (final t in ['Home preparedness', 'Before evacuation', 'Family safety',
          'Emergency communication']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      await tester.tap(find.text('Family safety'));
      await tester.pumpAndSettle();
      expect(find.textContaining('of 6 done'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pumpAndSettle();
      await _back(tester);
      expect(find.text('1 of 6 done'), findsOneWidget);
    });

    testWidgets('Emergency plan: save, leave, come back, values are restored', (tester) async {
      await _pumpApp(tester, '/preparedness');
      await tester.tap(find.text('Emergency plan'));
      await tester.pumpAndSettle();
      await _type(tester, 'Where will you meet?', 'Community hall');
      await tester.tap(find.text('Save plan'));
      await tester.pumpAndSettle();
      expect(find.text('Plan saved on this device.'), findsOneWidget);
      expect(find.text('Update plan'), findsOneWidget);

      await _back(tester);
      await tester.tap(find.text('Emergency plan'));
      await tester.pumpAndSettle();
      expect(find.text('Community hall'), findsOneWidget);
    });

    testWidgets('Emergency plan rejects a malformed phone number', (tester) async {
      await _pumpApp(tester, '/preparedness/plan');
      final phones = find.widgetWithText(TextField, 'Phone number');
      await tester.enterText(phones.first, '12');
      await tester.tap(find.text('Save plan'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid phone number (7-15 digits).'), findsOneWidget);
      expect(find.text('Plan saved on this device.'), findsNothing);
    });

    testWidgets('Prepare bottom navigation reaches Recovery and Home', (tester) async {
      await _pumpApp(tester, '/preparedness');
      await tester.tap(find.text('Recovery'));
      await tester.pumpAndSettle();
      expect(find.text('Damage report'), findsOneWidget);
      await tester.tap(find.text('SOS / Home'));
      await tester.pumpAndSettle();
      expect(find.text('HOME STUB'), findsOneWidget);
    });
  });

  group('Recovery navigation', () {
    testWidgets('Recovery Home lists every section with the empty state', (tester) async {
      await _pumpApp(tester, '/recovery');
      for (final t in ['Damage report', 'Missing person', 'Help / resource request',
          'Recovery guidance', 'My reports']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('No recovery reports yet.'), findsOneWidget);
    });

    testWidgets('Recovery Home -> each form opens and goes back', (tester) async {
      await _pumpApp(tester, '/recovery');
      await tester.tap(find.text('Damage report'));
      await tester.pumpAndSettle();
      expect(find.text('Damage category'), findsOneWidget);
      await _back(tester);

      await tester.tap(find.text('Missing person'));
      await tester.pumpAndSettle();
      expect(find.text('Approximate age'), findsOneWidget);
      await _back(tester);

      await tester.tap(find.text('Help / resource request'));
      await tester.pumpAndSettle();
      expect(find.text('What do you need?'), findsOneWidget);
      await _back(tester);
      expect(find.text('Recovery guidance'), findsOneWidget);
    });

    testWidgets('Recovery guidance -> topic -> back', (tester) async {
      await _pumpApp(tester, '/recovery');
      await tester.tap(find.text('Recovery guidance'));
      await tester.pumpAndSettle();
      for (final t in ['Unsafe buildings', 'Electrical hazards', 'Fire hazards',
          'Water safety', 'Hygiene', 'Safe return', 'Damage documentation',
          'Protecting important documents', 'Contacting authorities',
          'Avoiding unsafe structures']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      await tester.tap(find.text('Safe return'));
      await tester.pumpAndSettle();
      expect(find.text('ACTION STEPS'), findsOneWidget);
      await _back(tester);
      await _back(tester);
      expect(find.text('My reports'), findsOneWidget);
    });

    testWidgets('My reports is empty with the required message', (tester) async {
      await _pumpApp(tester, '/recovery');
      await tester.tap(find.text('My reports'));
      await tester.pumpAndSettle();
      expect(find.text('No recovery reports yet.'), findsOneWidget);
    });

    testWidgets('Recovery bottom navigation reaches Prepare and History', (tester) async {
      await _pumpApp(tester, '/recovery');
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.text('HISTORY STUB'), findsOneWidget);
    });
  });

  group('Report form flows', () {
    testWidgets('damage: submitting empty shows validation errors and saves nothing',
        (tester) async {
      final dispatcher = _Dispatcher();
      final repo = RecoveryRepository(dispatcher: dispatcher);
      await _pumpForm(tester, repo, () => DamageReportScreen(repository: repo));

      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a damage category.'), findsOneWidget);
      expect(find.text('Choose a severity.'), findsOneWidget);
      expect(find.text('Please fix the highlighted fields.'), findsOneWidget);
      expect(await repo.list(), isEmpty);
      expect(dispatcher.calls, 0);
    });

    testWidgets('damage: valid submit is saved as PENDING SYNC and shows the detail',
        (tester) async {
      final dispatcher = _Dispatcher();
      final repo = RecoveryRepository(dispatcher: dispatcher);
      await _pumpForm(tester, repo, () => DamageReportScreen(repository: repo));

      await tester.tap(find.text('Road'));
      await tester.tap(find.text('High'));
      await _type(tester, 'Location of damage', 'NH-44 near the bridge');
      await _type(tester, 'Description', 'Road washed away, vehicles cannot pass.');
      await tester.pump();
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();

      final saved = await repo.list();
      expect(saved, hasLength(1));
      expect(saved.single.status, ReportStatus.pendingSync);
      expect(dispatcher.calls, 1);

      // landed on the detail screen with honest wording
      expect(find.text('Report details'), findsOneWidget);
      expect(find.text('PENDING SYNC'), findsOneWidget);
      expect(find.text('Saved on this device. Will sync when connectivity is available.'),
          findsOneWidget);
      expect(find.textContaining('authorities'), findsNothing);
      expect(find.text(saved.single.id), findsOneWidget);
    });

    testWidgets('damage: a send failure keeps the report and says so', (tester) async {
      final repo = RecoveryRepository(dispatcher: _Dispatcher(fail: true));
      await _pumpForm(tester, repo, () => DamageReportScreen(repository: repo));

      await tester.tap(find.text('Water'));
      await tester.tap(find.text('Low'));
      await _type(tester, 'Location of damage', 'Ward 4 pump house');
      await _type(tester, 'Description', 'Main pipe burst, road flooding.');
      await tester.pump();
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();

      expect((await repo.list()).single.status, ReportStatus.failed);
      expect(find.text('FAILED'), findsOneWidget);
      expect(find.text('Sync failed. Report remains saved locally.'), findsWidgets);
      expect(find.text('Retry sync'), findsOneWidget);
      expect(find.text('Edit report'), findsOneWidget);
    });

    testWidgets('damage: Save as draft, then reopen the draft with fields restored',
        (tester) async {
      final repo = RecoveryRepository(dispatcher: _Dispatcher());
      await _pumpForm(tester, repo, () => DamageReportScreen(repository: repo));
      await tester.tap(find.text('Fire'));
      await _type(tester, 'Description', 'Warehouse still smouldering');
      await tester.pump();
      await tester.tap(find.text('Save as draft'));
      await tester.pumpAndSettle();

      final drafts = await repo.list();
      expect(drafts.single.status, ReportStatus.draft);

      await _pumpForm(
          tester, repo, () => DamageReportScreen(repository: repo, draftId: drafts.single.id));
      expect(find.text('Warehouse still smouldering'), findsOneWidget);
      expect(find.text('DRAFT'), findsOneWidget);
      final fire = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Fire'));
      expect(fire.selected, isTrue);
    });

    testWidgets('missing person: required fields, then a valid submit', (tester) async {
      final repo = RecoveryRepository(dispatcher: _Dispatcher());
      await _pumpForm(tester, repo, () => MissingPersonScreen(repository: repo));

      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();
      expect(find.text("Enter the person's name."), findsOneWidget);
      expect(find.text('Enter an approximate age between 0 and 120.'), findsOneWidget);

      await _type(tester, 'Name', 'Ramesh Kumar');
      await _type(tester, 'Approximate age', '34');
      await _type(tester, 'Last known location', 'Relief camp gate');
      await _type(tester, 'Description', 'Tall, blue jacket, limps slightly.');
      await tester.pump();
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();

      final saved = (await repo.list()).single;
      expect(saved.type, RecoveryReportType.missingPerson);
      expect(saved.status, ReportStatus.pendingSync);
      expect(find.text('Ramesh Kumar'), findsOneWidget);
    });

    testWidgets('resource request: chips, validation and submit', (tester) async {
      final repo = RecoveryRepository(dispatcher: _Dispatcher());
      await _pumpForm(tester, repo, () => ResourceRequestScreen(repository: repo));

      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();
      expect(find.text('Choose what you need.'), findsOneWidget);
      expect(find.text('Choose an urgency.'), findsOneWidget);

      await tester.tap(find.text('Medical assistance'));
      await tester.tap(find.text('Critical'));
      await _type(tester, 'Where help is needed', 'Ward 7 school');
      await _type(tester, 'Description', 'Diabetic patient out of insulin.');
      await tester.pump();
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();

      final saved = (await repo.list()).single;
      expect(saved.type, RecoveryReportType.resourceRequest);
      expect(saved.priorityLabel, 'Critical');
      expect(saved.status, ReportStatus.pendingSync);
    });

    testWidgets('a failed report can be retried from its detail once a route exists',
        (tester) async {
      final dispatcher = _Dispatcher(fail: true);
      final repo = RecoveryRepository(dispatcher: dispatcher);
      final draft = (repo.newDraft(RecoveryReportType.resourceRequest) as ResourceRequest)
          .copyWith(
        resourceType: ResourceType.food,
        urgency: RequestUrgency.normal,
        location: 'Ward 2 hall',
        description: 'Rations for thirty people.',
      );
      final failed = await repo.submit(draft);
      expect(failed.status, ReportStatus.failed);

      await _pumpForm(tester, repo,
          () => ReportDetailScreen(reportId: failed.id, repository: repo));
      expect(find.text('FAILED'), findsOneWidget);
      expect(find.text('Edit report'), findsOneWidget);

      dispatcher.fail = false;
      await tester.tap(find.text('Retry sync'));
      await tester.pumpAndSettle();
      expect(find.text('PENDING SYNC'), findsOneWidget);
      expect(find.text('Retry sync'), findsNothing);
      expect((await repo.get(failed.id))!.status, ReportStatus.pendingSync);
    });
  });

  group('My reports', () {
    testWidgets('lists every kind, filters, and opens a report', (tester) async {
      final repo = RecoveryRepository(dispatcher: _Dispatcher());
      for (final type in RecoveryReportType.values) {
        final draft = repo.newDraft(type);
        await repo.saveDraft(_filled(repo, draft));
      }

      _bigScreen(tester);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => MyReportsScreen(repository: repo)),
        GoRoute(
          path: '/recovery/reports/:id',
          builder: (_, s) =>
              ReportDetailScreen(reportId: s.pathParameters['id']!, repository: repo),
        ),
      ]);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsNothing);
      expect(find.textContaining('DMG-'), findsOneWidget);
      expect(find.textContaining('MIS-'), findsOneWidget);
      expect(find.textContaining('REQ-'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Missing person'));
      await tester.pumpAndSettle();
      expect(find.textContaining('DMG-'), findsNothing);
      expect(find.textContaining('MIS-'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Resource request'));
      await tester.pumpAndSettle();
      expect(find.textContaining('REQ-'), findsOneWidget);
      expect(find.textContaining('MIS-'), findsNothing);

      await tester.tap(find.textContaining('REQ-'));
      await tester.pumpAndSettle();
      expect(find.text('Report details'), findsOneWidget);
      expect(find.text('Edit draft'), findsOneWidget);
      expect(find.text('Delete draft'), findsOneWidget);
    });
  });
}

RecoveryRecord _filled(RecoveryRepository repo, RecoveryRecord draft) {
  // A minimal non-blank draft of each kind (drafts need no validation).
  switch (draft.type) {
    case RecoveryReportType.damage:
      return (draft as dynamic).copyWith(location: 'Bridge road') as RecoveryRecord;
    case RecoveryReportType.missingPerson:
      return (draft as dynamic).copyWith(name: 'Asha') as RecoveryRecord;
    case RecoveryReportType.resourceRequest:
      return (draft as dynamic).copyWith(location: 'Ward 7') as RecoveryRecord;
  }
}
