/// Local, MVP-level authorization check for who can terminate an emergency.
///
/// NOT the full fix — real responder authorization needs a backend-issued,
/// trusted registry (Ayush/Shaurya's territory, flagged since day one of
/// this design). This class exists so termination isn't left with ZERO
/// check while that backend piece is built: if the registry has been
/// populated (from the backend, once that endpoint exists), only those
/// keys are honored. If it's still empty (current MVP state, no backend
/// registry synced yet), termination is allowed through with a logged
/// warning — visible in logs, not silently unsafe.
class ResponderRegistry {
  ResponderRegistry._();
  static final ResponderRegistry instance = ResponderRegistry._();

  final Set<String> _trustedResponderPublicKeys = {};

  void syncFromBackend(List<String> responderPublicKeys) {
    _trustedResponderPublicKeys
      ..clear()
      ..addAll(responderPublicKeys);
  }

  /// Returns (isAuthorized, isEnforced) — isEnforced tells the caller
  /// whether this was a real check or just a pass-through because no
  /// registry has been synced yet.
  (bool authorized, bool enforced) checkResponder(String responderPublicKey) {
    if (_trustedResponderPublicKeys.isEmpty) {
      return (true, false); // TODO: remove pass-through once backend registry sync exists
    }
    return (_trustedResponderPublicKeys.contains(responderPublicKey), true);
  }
}