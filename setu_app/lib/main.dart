import 'package:flutter/material.dart';

import 'app.dart';
import 'core/services/connectivity_mesh_controller.dart';
import 'core/services/mesh_locator.dart';
import 'features/onboarding/presentation/screens/permission_gate_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Aug 5 2026 fix: this previously ran unconditionally at boot, before
  // the user had even reached (let alone completed) the permission gate
  // screen. On a fresh install that means MeshForegroundService starts
  // advertising/discovery immediately with location permission NOT YET
  // granted -- confirmed in a live device log showing
  // MISSING_PERMISSION_ACCESS_COARSE_LOCATION firing at app launch,
  // before any user interaction. hasMeshPermissions() (from
  // permission_gate_screen.dart) is the same check the gate screen
  // itself uses, so this only starts the connectivity-reactive mesh
  // layer once permissions are ACTUALLY already granted (e.g. this
  // isn't the first launch, or the user granted everything last time).
  // On a fresh install where permissions aren't granted yet, this is a
  // no-op here -- the permission gate screen's own _requestPermissions()
  // success path is what starts things up for that first-run case,
  // since MeshChannelHandler.start() (native side, unconditional) is
  // still what actually launches the foreground service either way;
  // this call only controls the CONNECTIVITY-REACTIVE layer on top.
  // Block 1: bring the Dart mesh pipeline up at startup, not lazily on
  // first SOS. Until MeshLocator exists there is no event-channel
  // listener, so nothing the native service receives can reach the
  // backend upload / ACK / responder-registry logic. Wrapped so a
  // failure here can never stop the app from launching.
  try {
    MeshLocator.start();
  } catch (_) {
    // Logged inside start(); the UI must still come up.
  }

  hasMeshPermissions().then((granted) {
    if (granted) {
      ConnectivityMeshController.instance.enableAutoMode();
    }
  });

  runApp(const SetuSOSApp());
}
