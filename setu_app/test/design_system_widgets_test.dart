// =====================================================
// SETU Project
// Module : Design System Widgets Tests
// =====================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';

void main() {
  group('SetuEmergencyButton Tests', () {
    testWidgets('renders SOS text and triggers callback on tap', (tester) async {
      bool triggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SetuEmergencyButton(
                triggerStyle: SetuEmergencyTriggerStyle.tap,
                onTriggered: () {
                  triggered = true;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('SOS'), findsOneWidget);
      expect(find.text('TAP TO CONFIRM'), findsOneWidget);

      await tester.tap(find.text('SOS'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(triggered, isTrue);
    });

    testWidgets('renders in hold mode with hold-to-activate label', (tester) async {
      bool triggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SetuEmergencyButton(
                triggerStyle: SetuEmergencyTriggerStyle.hold,
                holdDuration: const Duration(milliseconds: 500),
                onTriggered: () {
                  triggered = true;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('SOS'), findsOneWidget);
      expect(find.text('HOLD 3 SECONDS'), findsOneWidget);

      await tester.tap(find.text('SOS'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(triggered, isFalse);
    });
  });

  group('SetuButton Tests', () {
    testWidgets('renders label and handles tap', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SetuButton(
                label: 'CONFIRM DISPATCH',
                icon: Icons.send_rounded,
                onPressed: () {
                  tapped = true;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('CONFIRM DISPATCH'), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);

      await tester.tap(find.text('CONFIRM DISPATCH'));
      expect(tapped, isTrue);
    });

    testWidgets('shows loading indicator when isLoading is true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SetuButton(
                label: 'TRANSMITTING...',
                isLoading: true,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('disabled button does not trigger callback', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SetuButton(
                label: 'DISABLED',
                onPressed: null,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('DISABLED'));
      expect(tapped, isFalse);
    });
  });

  group('SetuStatusIndicator Tests', () {
    testWidgets('renders online status correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SetuStatusIndicator(
                status: SetuStatusType.online,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Online · Network Ready'), findsOneWidget);
    });

    testWidgets('renders meshActive status with reassuring text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SetuStatusIndicator(
                status: SetuStatusType.meshActive,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Offline · Mesh Active'), findsOneWidget);
    });

    testWidgets('renders offline status clearly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SetuStatusIndicator(
                status: SetuStatusType.offline,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Offline · Standby'), findsOneWidget);
    });
  });

  group('SetuOfflineBanner Tests', () {
    testWidgets('displays offline mesh banner and taps callback', (tester) async {
      bool bannerTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SetuOfflineBanner(
              isOffline: true,
              peerCount: 3,
              onTap: () {
                bannerTapped = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Offline Mode · Mesh Active'), findsOneWidget);
      expect(
        find.text('3 nearby SETU peer(s) found. Emergency alerts will relay automatically.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Offline Mode · Mesh Active'));
      expect(bannerTapped, isTrue);
    });
  });

  group('SetuBottomNavigation Tests', () {
    testWidgets('renders all 4 emergency tabs and highlights current index', (tester) async {
      int selectedTab = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: SetuBottomNavigation(
              currentIndex: 0,
              onTap: (index) {
                selectedTab = index;
              },
            ),
          ),
        ),
      );

      expect(find.text('SOS / Home'), findsOneWidget);
      expect(find.text('Prepare'), findsOneWidget);
      expect(find.text('Recovery'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);

      await tester.tap(find.text('Prepare'));
      expect(selectedTab, 1);

      await tester.tap(find.text('History'));
      expect(selectedTab, 3);
    });
  });

  group('SetuIncidentStatusBadge Tests', () {
    testWidgets('displays status labels with appropriate icons', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SetuIncidentStatusBadge(state: SetuIncidentState.pending),
                SetuIncidentStatusBadge(state: SetuIncidentState.relaying),
                SetuIncidentStatusBadge(state: SetuIncidentState.delivered),
              ],
            ),
          ),
        ),
      );

      expect(find.text('PENDING'), findsOneWidget);
      expect(find.text('RELAYING'), findsOneWidget);
      expect(find.text('DELIVERED'), findsOneWidget);
    });
  });
}
