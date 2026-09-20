import '../enums/packet_type.dart';
import 'ack_packet.dart';
import 'alert_packet.dart';
import 'emergency_packet.dart';
import 'mesh_packet.dart';
import 'termination_packet.dart';

class PacketFactory {
  const PacketFactory._();

  static MeshPacket fromJson(Map<String, dynamic> json) {
    final packetType = PacketType.values.byName(json['type']);

    switch (packetType) {
      case PacketType.emergency:
        return EmergencyPacket.fromJson(json);

      case PacketType.termination:
        return TerminationPacket.fromJson(json);

      // Added Aug 4 2026 -- see ack_packet.dart / alert_packet.dart.
      case PacketType.ack:
        return AckPacket.fromJson(json);

      case PacketType.alert:
        return AlertPacket.fromJson(json);
    }
  }
}
