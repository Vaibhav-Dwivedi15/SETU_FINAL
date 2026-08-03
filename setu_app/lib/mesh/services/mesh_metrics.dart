import 'dart:developer' as developer;

class MeshMetrics {
  MeshMetrics._();

  static final instance = MeshMetrics._();

  int sent = 0;
  int received = 0;
  int relayed = 0;
  int uploaded = 0;
  int dropped = 0;

  void log() {
    developer.log(
      '''
Mesh Metrics

Sent      : $sent
Received  : $received
Relayed   : $relayed
Uploaded  : $uploaded
Dropped   : $dropped
''',
      name: 'MeshMetrics',
    );
  }

  void reset() {
    sent = 0;
    received = 0;
    relayed = 0;
    uploaded = 0;
    dropped = 0;
  }
}