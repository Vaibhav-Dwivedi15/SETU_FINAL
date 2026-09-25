// =====================================================
// SETU Project
// Module : Prepare (guides, kit, checklists, plan, contacts) tests
// =====================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setu_app/features/preparedness/data/models/disaster_type.dart';
import 'package:setu_app/features/preparedness/data/models/emergency_contact.dart';
import 'package:setu_app/features/preparedness/data/models/emergency_plan.dart';
import 'package:setu_app/features/preparedness/data/models/guide_section.dart';
import 'package:setu_app/features/preparedness/data/repositories/checklist_repository.dart';
import 'package:setu_app/features/preparedness/data/repositories/emergency_contacts_repository.dart';
import 'package:setu_app/features/preparedness/data/repositories/emergency_plan_repository.dart';
import 'package:setu_app/features/preparedness/data/services/preparedness_service.dart';
import 'package:setu_app/features/preparedness/presentation/screens/emergency_contacts_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Disaster guides', () {
    test('all five required disasters are bundled with Before/During/After/Avoid', () async {
      final guides = await PreparednessService.instance.loadGuides();
      for (final type in DisasterType.values) {
        final guide = guides.where((g) => g.id == type.id).toList();
        expect(guide, hasLength(1), reason: '${type.id} guide missing');
        final kinds = guide.single.sections.map((s) => s.kind).toList();
        expect(kinds, [
          GuideSectionKind.before,
          GuideSectionKind.during,
          GuideSectionKind.after,
          GuideSectionKind.avoid,
        ], reason: '${type.id} must have all four phases in order');
        for (final s in guide.single.sections) {
          expect(s.items, isNotEmpty);
        }
        expect(guide.single.disasterType, type);
      }
    });

    test('guides come from the bundled asset only (offline)', () async {
      final requestedPaths = <String>[];
      final library = GuideLibrary(
        assetPath: 'assets/preparedness/safety_guides.json',
        listKey: 'guides',
        loader: (path) async {
          requestedPaths.add(path);
          return '{"guides":[{"id":"x","title":"X","summary":"s","steps":["a"]}]}';
        },
      );
      final guides = await library.loadGuides();
      expect(requestedPaths, ['assets/preparedness/safety_guides.json']);
      expect(guides.single.sections.single.kind, GuideSectionKind.steps);
      await library.loadGuides();
      expect(requestedPaths, hasLength(1), reason: 'parsed once, then cached');
    });

    test('a new disaster type needs only JSON, not code', () async {
      final library = GuideLibrary(
        assetPath: 'a',
        listKey: 'guides',
        loader: (_) async =>
            '{"guides":[{"id":"tsunami","title":"Tsunami","summary":"s","sections":{"before":["a"],"avoid":["b"]}}]}',
      );
      final tsunami = await library.guideById('tsunami');
      expect(tsunami!.sections.map((s) => s.kind),
          [GuideSectionKind.before, GuideSectionKind.avoid]);
      expect(tsunami.disasterType, isNull);
    });

    test('a corrupt asset yields an empty list instead of throwing', () async {
      final library = GuideLibrary(assetPath: 'a', listKey: 'guides', loader: (_) async => '{nope');
      expect(await library.loadGuides(), isEmpty);
    });

    test('pre-existing non-disaster guides are still bundled', () async {
      final guides = await PreparednessService.instance.loadGuides();
      for (final id in ['accident', 'women_safety', 'child_safety', 'senior_citizen']) {
        expect(guides.any((g) => g.id == id), isTrue, reason: id);
      }
    });
  });

  group('Checklists', () {
    test('catalog has the emergency kit and the four required checklists', () async {
      final ids = (await ChecklistRepository().loadChecklists()).map((c) => c.id).toList();
      expect(ids, containsAll([
        'emergency_kit',
        'home_preparedness',
        'before_evacuation',
        'family_safety',
        'emergency_communication',
      ]));
    });

    test('emergency kit has the required items, grouped by category', () async {
      final kit = (await ChecklistRepository().checklistById('emergency_kit'))!;
      final text = kit.items.map((i) => i.text.toLowerCase()).join('|');
      for (final needle in [
        'water', 'food', 'first-aid', 'medicines', 'torch', 'power bank',
        'batteries', 'documents', 'whistle', 'tools', 'masks', 'sanitation'
      ]) {
        expect(text, contains(needle));
      }
      expect(kit.itemsByCategory.keys.whereType<String>().length, greaterThan(2));
    });

    test('completion is counted and persisted across repository instances', () async {
      final first = ChecklistRepository();
      final kit = (await first.checklistById('emergency_kit'))!;
      await first.setItemDone('emergency_kit', kit.items[0].id, true);
      await first.setItemDone('emergency_kit', kit.items[1].id, true);

      final reopened = await ChecklistRepository().progressFor('emergency_kit');
      expect(reopened!.completed, 2);
      expect(reopened.remaining, kit.items.length - 2);
      expect(reopened.fraction, closeTo(2 / kit.items.length, 1e-9));
      expect(reopened.isDone(kit.items[0]), isTrue);
      expect(reopened.isDone(kit.items[2]), isFalse);
    });

    test('unchecking removes the item; checklists are independent', () async {
      final repo = ChecklistRepository();
      final home = (await repo.checklistById('home_preparedness'))!;
      await repo.setItemDone('home_preparedness', home.items[0].id, true);
      await repo.setItemDone('home_preparedness', home.items[0].id, false);
      expect((await repo.progressFor('home_preparedness'))!.completed, 0);

      await repo.setItemDone('family_safety', 'family_01', true);
      expect((await repo.progressFor('home_preparedness'))!.completed, 0);
      expect((await repo.progressFor('family_safety'))!.completed, 1);
    });

    test('reset clears only that checklist', () async {
      final repo = ChecklistRepository();
      await repo.setItemDone('emergency_kit', 'kit_01', true);
      await repo.setItemDone('family_safety', 'family_01', true);
      await repo.reset('emergency_kit');
      expect((await repo.progressFor('emergency_kit'))!.completed, 0);
      expect((await repo.progressFor('family_safety'))!.completed, 1);
    });

    test('stored ids that no longer exist do not inflate progress', () async {
      SharedPreferences.setMockInitialValues({
        'checklist_done_emergency_kit': ['kit_01', 'removed_item'],
      });
      expect((await ChecklistRepository().progressFor('emergency_kit'))!.completed, 1);
    });

    test('completing every item marks the checklist complete', () async {
      final repo = ChecklistRepository();
      final c = (await repo.checklistById('family_safety'))!;
      for (final item in c.items) {
        await repo.setItemDone(c.id, item.id, true);
      }
      final p = (await repo.progressFor(c.id))!;
      expect(p.isComplete, isTrue);
      expect(p.remaining, 0);
    });
  });

  group('Emergency plan', () {
    const plan = EmergencyPlan(
      primaryName: 'Asha',
      primaryPhone: '9876543210',
      secondaryName: 'Ravi',
      secondaryPhone: '+91 91234 56780',
      meetingPoint: 'Community hall',
      notes: 'Insulin in fridge',
    );

    test('loads empty when nothing is saved', () async {
      expect((await EmergencyPlanRepository().load()).isEmpty, isTrue);
    });

    test('save then load returns the same plan (new instance)', () async {
      await EmergencyPlanRepository().save(plan);
      final loaded = await EmergencyPlanRepository().load();
      expect(loaded.toJson(), plan.toJson());
    });

    test('update overwrites, clear removes', () async {
      final repo = EmergencyPlanRepository();
      await repo.save(plan);
      await repo.save(plan.copyWith(meetingPoint: 'School ground'));
      expect((await repo.load()).meetingPoint, 'School ground');
      await repo.clear();
      expect((await repo.load()).isEmpty, isTrue);
    });

    test('a corrupt stored plan reads as empty', () async {
      SharedPreferences.setMockInitialValues({'emergency_plan': '{broken'});
      expect((await EmergencyPlanRepository().load()).isEmpty, isTrue);
    });

    test('phone validation: optional, but 7-15 digits when present', () {
      expect(const EmergencyPlan().validate(), isEmpty);
      expect(plan.validate(), isEmpty);
      expect(plan.copyWith(primaryPhone: '123').validate().keys, ['primaryPhone']);
      expect(plan.copyWith(secondaryPhone: 'abc').validate().keys, ['secondaryPhone']);
    });
  });

  group('Emergency contacts', () {
    test('lists plan contacts then saved SOS contacts, without duplicates', () async {
      SharedPreferences.setMockInitialValues({
        'emergency_contacts':
            '[{"name":"Asha (saved)","phone":"9876543210"},{"name":"Meena","phone":"9000000001"}]',
      });
      await EmergencyPlanRepository().save(const EmergencyPlan(
        primaryName: 'Asha',
        primaryPhone: '9876543210',
        secondaryName: '',
        secondaryPhone: '+91 90000 00002',
      ));

      final contacts = await EmergencyContactsRepository().load();
      expect(contacts.map((c) => c.name), ['Asha', 'Secondary emergency contact', 'Meena']);
      expect(contacts.first.source, EmergencyContactSource.plan);
      expect(contacts.last.source, EmergencyContactSource.saved);
    });

    test('bundles no official numbers of its own: empty when the user saved none', () async {
      expect(await EmergencyContactsRepository().load(), isEmpty);
    });

    test('dial URI keeps only dialable characters', () {
      const c = EmergencyContact(
          name: 'A', purpose: 'p', phone: '+91 (98765) 43210', source: EmergencyContactSource.saved);
      expect(c.dialUri.toString(), 'tel:+919876543210');
    });

    Future<void> pumpScreen(WidgetTester tester, DialLauncher launcher) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => EmergencyContactsScreen(dialLauncher: launcher)),
      ]);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
    }

    testWidgets('shows contacts and reports only what actually happened when calling',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'emergency_contacts': '[{"name":"Meena","phone":"9000000001"}]',
      });
      final dialed = <Uri>[];
      await pumpScreen(tester, (uri) async {
        dialed.add(uri);
        return true;
      });
      expect(find.text('Meena'), findsOneWidget);
      expect(find.text('9000000001'), findsOneWidget);

      await tester.tap(find.byTooltip('Call Meena'));
      await tester.pump();
      expect(dialed.single.toString(), 'tel:9000000001');
      expect(find.text('Opening the phone app for Meena.'), findsOneWidget);
    });

    testWidgets('does not claim a call when the dialer cannot be opened', (tester) async {
      SharedPreferences.setMockInitialValues({
        'emergency_contacts': '[{"name":"Meena","phone":"9000000001"}]',
      });
      await pumpScreen(tester, (_) async => false);
      await tester.tap(find.byTooltip('Call Meena'));
      await tester.pump();
      expect(find.textContaining('Could not open the phone app'), findsOneWidget);
      expect(find.textContaining('Opening the phone app'), findsNothing);
    });

    testWidgets('empty state explains there are no bundled official numbers', (tester) async {
      await pumpScreen(tester, (_) async => true);
      expect(find.text('No emergency contacts yet'), findsOneWidget);
      expect(find.textContaining('does not include official'), findsOneWidget);
    });
  });
}
