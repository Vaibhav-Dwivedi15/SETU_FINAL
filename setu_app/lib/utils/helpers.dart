import 'dart:math';

/// Generates short, unique, hard-to-guess hex strings — used for packet
/// IDs and nonces. Not cryptographic identity, just uniqueness.
class IdGenerator {
  static final _rand = Random.secure();

  static String generate({int bytes = 16}) {
    final values = List<int>.generate(bytes, (_) => _rand.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}