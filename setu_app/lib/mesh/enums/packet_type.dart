enum PacketType {
  emergency,
  termination,
  // Added Aug 4 2026 -- see ack_packet.dart / alert_packet.dart for why.
  ack,
  alert,
}
