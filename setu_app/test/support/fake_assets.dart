import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests run in fake-async, but rootBundle answers through real
/// file IO, so an asset load can hang forever inside `pumpAndSettle`.
/// This serves the app's bundled assets from memory through the asset
/// channel instead, so loads complete without real IO.
///
/// Call [readBundledAssets] once (setUpAll, outside fake-async) and
/// [serveBundledAssets] in setUp.
final Map<String, Uint8List> _assets = {};

Future<void> readBundledAssets(List<String> paths) async {
  for (final path in paths) {
    _assets[path] = await File(path).readAsBytes();
  }
}

void serveBundledAssets() {
  rootBundle.clear();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (ByteData? message) async {
    final key = utf8.decode(message!.buffer.asUint8List());
    final bytes = _assets[key];
    return bytes == null ? null : ByteData.sublistView(bytes);
  });
}
