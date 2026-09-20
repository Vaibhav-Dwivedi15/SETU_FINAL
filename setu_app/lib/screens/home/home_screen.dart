import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../security/security_constants.dart';
import '../../mesh/enums/emergency_priority.dart';
import '../../mesh/models/emergency_packet.dart';
import '../../mesh/models/mesh_packet.dart';
import '../../mesh/services/identity_service.dart';
import '../../mesh/services/mesh_service.dart';
import '../../mesh/services/nearby_service.dart';
import '../../mesh/services/signing_service.dart';
import '../../services/backend_service.dart';
import '../../utils/helpers.dart';
import '../../mesh/services/local_queue_service.dart';
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final MeshService _meshService;
  final SigningService _signing = SigningService();
  late final IdentityService _identity;
  final List<String> _log = [];
  String? _senderId;
  bool _starting = true;
  StreamSubscription<MeshPacket>? _packetSub;

  @override
  void initState() {
    super.initState();
    _identity = IdentityService(_signing);
    _meshService = MeshServiceImpl(
      nearbyService: PlatformNearbyService(),
      signingService: _signing,
      backendService: BackendService(),
      queueService: LocalQueueService(),
    );
    _init();
  }

  Future<void> _init() async {
    final granted = await _requestPermissions();
    _senderId = await _identity.getOrCreateSenderId();
    setState(() => _starting = false);

    if (!granted) return;

    _packetSub = _meshService.incomingPackets.listen(_onPacketReceived);
    _appendLog('Mesh started. Sender ID: ${_senderId!.substring(0, 8)}...');
  }

  Future<bool> _requestPermissions() async {
    // Bluetooth + Location are required on every Android version we
    // support — block on these.
    final requiredStatuses = await [
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    // NEARBY_WIFI_DEVICES only exists as an OS concept on Android 13+.
    // On older Android (e.g. Android 10), permission_handler can report
    // this as "denied" simply because the OS never registered it at all
    // — that is NOT a real missing permission on those devices, so it
    // must never block mesh startup.
    final nearbyWifiStatus = await Permission.nearbyWifiDevices.request();
    if (!nearbyWifiStatus.isGranted) {
      _appendLog('Note: nearbyWifiDevices not granted (expected on Android <13) — continuing anyway.');
    }

    final denied = requiredStatuses.entries.where((e) => !e.value.isGranted).toList();
    if (denied.isNotEmpty) {
      _appendLog(
        'Missing permissions: ${denied.map((e) => e.key.toString()).join(", ")} — '
        'grant these in Settings > Apps > SETU > Permissions, then restart the app.',
      );
      return false;
    }
    return true;
  }

  void _onPacketReceived(MeshPacket packet) {
    _appendLog(
      'Received ${packet.type.name} packet from ${packet.senderId.substring(0, 8)}... '
      '(hop ${packet.hopCount}, ttl ${packet.ttl}) — signature verified',
    );
  }

  void _appendLog(String line) {
    setState(() => _log.insert(0, line));
  }

  /// Never blocks SOS sending on GPS — an emergency should go out even if
  /// location can't be fetched in time.
  Future<(double, double)> _getLocationOrFallback() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _appendLog('Location services OFF — sending SOS without GPS (0,0 placeholder).');
        return (0.0, 0.0);
      }

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _appendLog('Location permission missing — sending SOS without GPS (0,0 placeholder).');
        return (0.0, 0.0);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return (position.latitude, position.longitude);
    } catch (e) {
      _appendLog('GPS fetch failed ($e) — sending SOS without GPS (0,0 placeholder).');
      return (0.0, 0.0);
    }
  }

  Future<void> _sendTestSos() async {
    if (_senderId == null) return;

    final (lat, lng) = await _getLocationOrFallback();

    final unsigned = EmergencyPacket(
      packetId: IdGenerator.generate(),
      senderId: _senderId!,
      timestamp: DateTime.now(),
      nonce: IdGenerator.generate(),
      ttl: SecurityConstants.defaultTTL, // was hardcoded 8 — now matches Security Lead's documented maxTTL=5
      hopCount: 0,
      signature: '',
      emergencyId: IdGenerator.generate(),
      latitude: lat,
      longitude: lng,
      message: 'Test SOS from ${_senderId!.substring(0, 8)}',
      priority: EmergencyPriority.high,
    );

    final signatureHex = await _signing.sign(unsigned.signaturePayload);
    final packet = unsigned.copyWith(signature: signatureHex);

    await _meshService.originate(packet);
    _appendLog('Sent SIGNED test SOS: ${packet.packetId.substring(0, 8)}... (lat: $lat, lng: $lng)');
  }

  @override
  void dispose() {
    _packetSub?.cancel();
    _meshService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SETU — Mesh Test')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_starting) const CircularProgressIndicator(),
            if (!_starting)
              ElevatedButton(
                onPressed: _sendTestSos,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('SEND TEST SOS', style: TextStyle(fontSize: 18)),
              ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _log.length,
                itemBuilder: (context, i) => Text(_log[i], style: const TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}