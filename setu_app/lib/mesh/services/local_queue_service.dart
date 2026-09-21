import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/mesh_packet.dart';
import '../models/packet_factory.dart';

/// Durable store-and-forward queue — Phase 6 from the original Role 1
/// roadmap, always in scope, just not built until now.
///
/// Different from the native PacketRelayEngine's in-memory seen-ID cache:
/// that one prevents relay loops in real time and is intentionally
/// ephemeral. This one persists to disk, so a packet a device is carrying
/// survives an app restart, a phone reboot, or just not finding an exit
/// node for hours — and gets uploaded whenever connectivity eventually
/// shows up, not only at the single moment it first arrived.
class LocalQueueService {
  static const _dbName = 'setu_queue.db';
  static const _table = 'packets';

  Database? _db;

  Future<void> init() async {
    if (_db != null) return;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) {
        return db.execute('''
          CREATE TABLE $_table (
            packetId TEXT PRIMARY KEY,
            jsonPayload TEXT NOT NULL,
            createdAtMillis INTEGER NOT NULL,
            uploaded INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );
  }

  /// Stores a packet if it isn't already queued. Safe for both
  /// self-originated and relayed-through packets.
  Future<void> enqueue(MeshPacket packet) async {
    await init();
    await _db!.insert(
      _table,
      {
        'packetId': packet.packetId,
        'jsonPayload': jsonEncode(packet.toJson()),
        'createdAtMillis': DateTime.now().millisecondsSinceEpoch,
        'uploaded': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore, // already queued — no-op
    );
  }

  Future<void> markUploaded(String packetId) async {
    await init();
    await _db!.update(
      _table,
      {'uploaded': 1},
      where: 'packetId = ?',
      whereArgs: [packetId],
    );
  }

  /// Packets still waiting to reach the backend.
  Future<List<MeshPacket>> getPendingPackets() async {
    await init();
    final rows = await _db!.query(_table, where: 'uploaded = 0');
    final packets = <MeshPacket>[];
    for (final row in rows) {
      try {
        final json = jsonDecode(row['jsonPayload'] as String) as Map<String, dynamic>;
        packets.add(PacketFactory.fromJson(json));
      } catch (_) {
        // Malformed row — skip it rather than crash the whole queue.
      }
    }
    return packets;
  }

  /// Deletes already-uploaded packets older than [maxAge], so the local DB
  /// doesn't grow forever. Never touches anything still pending upload.
  Future<void> pruneUploaded({Duration maxAge = const Duration(days: 3)}) async {
    await init();
    final cutoff = DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
    await _db!.delete(
      _table,
      where: 'uploaded = 1 AND createdAtMillis < ?',
      whereArgs: [cutoff],
    );
  }

  /// Removes every queued packet belonging to a now-closed emergency —
  /// stops retrying uploads for an incident that's already resolved.
  /// Called once a verified TerminationPacket is processed.
  ///
  /// [keepPacketId], if given, is excluded from the sweep. This exists so
  /// the TerminationPacket that *caused* the closure can itself still be
  /// enqueued and uploaded to the backend — without it, a termination
  /// enqueued after this sweep runs has nothing left to ever clear it,
  /// since there is only ever one termination per emergency_id (found via
  /// real `flutter test` execution, Bulk Sprint 5 Phase 18 — see
  /// docs/mesh/SPRINT5_INTEGRATION_VALIDATION.md §15).
  Future<void> markEmergencyClosed(String emergencyId, {String? keepPacketId}) async {
    await init();
    if (keepPacketId != null) {
      await _db!.delete(
        _table,
        where: 'jsonPayload LIKE ? AND packetId != ?',
        whereArgs: ['%"emergency_id":"$emergencyId"%', keepPacketId],
      );
    } else {
      await _db!.delete(
        _table,
        where: 'jsonPayload LIKE ?',
        whereArgs: ['%"emergency_id":"$emergencyId"%'],
      );
    }
  }
}