import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

/// Authorization check for who can terminate an emergency.
///
/// Block 1 (mesh-stability) -- this used to FAIL OPEN: while the trusted
/// key set was empty (never synced, or the process had just restarted --
/// the set was memory-only) every validly-signed termination from ANY
/// key was honoured. Any device could therefore close an emergency on
/// every phone that had not yet synced, which is the normal state of an
/// offline mesh.
///
/// Now:
///  * the last successfully-synced key set is PERSISTED and reloaded
///    (see [ensureLoaded]), so a restart does not forget it;
///  * an empty set means "no trusted responders known" and every
///    termination is REJECTED (fail closed). A responder must be
///    provisioned on the backend and synced at least once before a mesh
///    termination can take effect.
///
/// A termination is only ever an authorization decision on `senderId`
/// (the Ed25519 key that signed the packet), never on the informational
/// `responderId` field -- see TerminationPacket.
class ResponderRegistry {
  ResponderRegistry._();
  static final ResponderRegistry instance = ResponderRegistry._();

  static const _prefsKey = 'setu_responder_registry_v1';

  final Set<String> _trustedResponderPublicKeys = {};
  Future<void>? _loading;

  /// Loads the persisted key set once. Safe to call repeatedly and
  /// concurrently. Storage failure is non-fatal: the registry then simply
  /// stays empty (fail closed) until a backend sync succeeds.
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_prefsKey);
      // Never let a stale disk copy override a fresher in-memory sync.
      if (stored != null && _trustedResponderPublicKeys.isEmpty) {
        _trustedResponderPublicKeys.addAll(stored.where((k) => k.isNotEmpty));
      }
    } catch (e) {
      developer.log('Responder registry load failed (staying fail-closed): $e',
          name: 'ResponderRegistry');
    }
  }

  /// Replaces the trusted set with what the backend returned and persists
  /// it. An empty list from a SUCCESSFUL fetch is authoritative: no
  /// trusted responders.
  void syncFromBackend(List<String> responderPublicKeys) {
    _trustedResponderPublicKeys
      ..clear()
      ..addAll(responderPublicKeys.where((k) => k.isNotEmpty));
    _loading ??= Future<void>.value(); // a fresh sync supersedes any pending load
    _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, _trustedResponderPublicKeys.toList());
    } catch (e) {
      developer.log('Responder registry persist failed: $e', name: 'ResponderRegistry');
    }
  }

  int get trustedCount => _trustedResponderPublicKeys.length;

  /// Returns `(authorized, registryAvailable)`.
  ///
  /// `registryAvailable == false` means there is no key set at all, in
  /// which case `authorized` is always false (fail closed) -- callers use
  /// the flag only to log a more useful reason.
  (bool authorized, bool registryAvailable) checkResponder(String responderPublicKey) {
    if (_trustedResponderPublicKeys.isEmpty) {
      return (false, false);
    }
    return (_trustedResponderPublicKeys.contains(responderPublicKey), true);
  }

  /// Test hook: behave like a process restart -- forget the in-memory set
  /// but keep whatever was persisted.
  void simulateRestartForTesting() {
    _trustedResponderPublicKeys.clear();
    _loading = null;
  }

  /// Test hook: forget everything, in memory and on disk.
  Future<void> resetForTesting() async {
    _trustedResponderPublicKeys.clear();
    _loading = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }
}
