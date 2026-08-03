import 'package:flutter/material.dart';

import 'app.dart';
import 'core/services/connectivity_mesh_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Added Aug 4 2026: without this call the mesh service still starts
  // fine (MeshChannelHandler.start() runs unconditionally from
  // MainActivity, same as before) -- this just adds the connectivity-
  // reactive layer on top. Safe to call unconditionally; see
  // ConnectivityMeshController's own docstring for exactly what it
  // does and doesn't change about default behavior.
  ConnectivityMeshController.instance.enableAutoMode();

  runApp(const SetuSOSApp());
}
