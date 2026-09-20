import 'package:flutter/material.dart';

import 'app.dart';
import 'core/services/connectivity_mesh_controller.dart';
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
  hasMeshPermissions().then((granted) {
    if (granted) {
      ConnectivityMeshController.instance.enableAutoMode();
    }
  });

  runApp(const SetuSOSApp());
}
