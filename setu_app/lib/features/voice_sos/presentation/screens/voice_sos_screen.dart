// =====================================================
// SETU Project
// Module : Voice SOS (new)
// Owner  : Sudheer
// =====================================================
//
// NEW DEPENDENCY REQUIRED: this screen needs an audio recording
// package, which pubspec.yaml does not currently have. Add before this
// compiles:
//   record: ^5.1.2
// (any actively-maintained version compatible with the project's
// Flutter SDK is fine — `record` was chosen over `flutter_sound`
// because its API surface is smaller and this screen only needs
// start/stop/save-to-file, nothing more).
//
// ANDROID MANIFEST: add RECORD_AUDIO — it is NOT currently present in
// android/app/src/main/AndroidManifest.xml (checked directly):
//   <uses-permission android:name="android.permission.RECORD_AUDIO" />
//
// MIC PERMISSION IS REQUESTED HERE, NOT IN THE MESH PERMISSION GATE:
// deliberately decoupled from permission_gate_screen.dart's BLE/Wi-Fi/
// location bundle, since a user who never uses voice SOS shouldn't be
// asked for microphone access at first launch. It's requested the first
// time this screen is opened instead.
//
// CONNECTIVITY: voice SOS requires a direct internet connection to the
// backend (see services/voice_sos_service.dart's module docstring on
// why — audio can't travel the offline mesh). This screen checks
// availability on open and disables recording with a clear message if
// the backend can't process voice right now, rather than letting a user
// record something that goes nowhere.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/app_button.dart';
import 'package:setu_app/features/location/data/services/location_service.dart';
import 'package:setu_app/mesh/services/signing_service.dart';
import 'package:setu_app/core/language/app_strings.dart';
import 'package:setu_app/services/voice_sos_service.dart';

enum _VoiceState { checking, unavailable, idle, recording, uploading, done, error }

class VoiceSosScreen extends StatefulWidget {
  const VoiceSosScreen({super.key});

  @override
  State<VoiceSosScreen> createState() => _VoiceSosScreenState();
}

class _VoiceSosScreenState extends State<VoiceSosScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  final VoiceSosService _voiceService = VoiceSosService();
  final LocationService _locationService = LocationService();
  final SigningService _signingService = SigningService();

  _VoiceState _state = _VoiceState.checking;
  String? _statusMessage;
  String? _transcript;
  String? _recordingPath;
  Duration _elapsed = Duration.zero;
  DateTime? _recordingStartedAt;

  @override
  void initState() {
    super.initState();
    _checkAvailability();
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _checkAvailability() async {
    final availability = await _voiceService.checkAvailability();
    if (!mounted) return;
    setState(() {
      _state = availability.available ? _VoiceState.idle : _VoiceState.unavailable;
      _statusMessage = availability.detail;
    });
  }

  Future<void> _startRecording() async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      if (!mounted) return;
      setState(() {
        _state = _VoiceState.error;
        _statusMessage = 'Microphone permission is required to record a voice SOS.';
      });
      return;
    }

    if (!await _recorder.hasPermission()) {
      if (!mounted) return;
      setState(() {
        _state = _VoiceState.error;
        _statusMessage = 'Microphone permission is required to record a voice SOS.';
      });
      return;
    }

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/setu_voice_sos_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(const RecordConfig(), path: path);

    if (!mounted) return;
    setState(() {
      _state = _VoiceState.recording;
      _recordingPath = path;
      _recordingStartedAt = DateTime.now();
      _elapsed = Duration.zero;
    });

    _tickElapsed();
  }

  void _tickElapsed() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted || _state != _VoiceState.recording || _recordingStartedAt == null) return;
      setState(() {
        _elapsed = DateTime.now().difference(_recordingStartedAt!);
      });
      _tickElapsed();
    });
  }

  Future<void> _stopAndSend() async {
    final path = await _recorder.stop();
    if (!mounted) return;

    final resolvedPath = path ?? _recordingPath;
    if (resolvedPath == null) {
      setState(() {
        _state = _VoiceState.error;
        _statusMessage = 'Recording failed — no audio file was produced.';
      });
      return;
    }

    setState(() {
      _state = _VoiceState.uploading;
      _statusMessage = 'Sending voice SOS...';
    });

    // Reuses the same device identity (senderId = hex Ed25519 public
    // key, persisted in secure storage — see signing_service.dart) and
    // current location the mesh SOS flow uses, so voice SOS is
    // consistent with the rest of the app's identity/location handling
    // rather than inventing a separate path.
    //
    // Location is best-effort: LocationService.getCurrentLocation()
    // throws if location services/permission aren't available. Rather
    // than block the whole voice SOS on that, this falls back to
    // (0.0, 0.0) -- the frozen packet spec's own documented
    // no-GPS-fix convention (see emergency_packet_builder.dart) -- so a
    // location failure never prevents the report itself from sending.
    final senderId = await _signingService.getOrCreatePublicKeyHex();

    double latitude = 0.0;
    double longitude = 0.0;
    try {
      final location = await _locationService.getCurrentLocation();
      latitude = location.latitude;
      longitude = location.longitude;
    } catch (_) {
      // Fall through with (0.0, 0.0) — see comment above.
    }

    final result = await _voiceService.uploadVoiceSos(
      audioFile: File(resolvedPath),
      senderId: senderId,
      latitude: latitude,
      longitude: longitude,
    );

    if (!mounted) return;

    setState(() {
      _state = result.success ? _VoiceState.done : _VoiceState.error;
      _statusMessage = result.detail;
      _transcript = result.transcript;
    });
  }

  Future<void> _cancelRecording() async {
    await _recorder.stop();
    if (!mounted) return;
    setState(() {
      _state = _VoiceState.idle;
      _recordingPath = null;
      _elapsed = Duration.zero;
    });
  }

  String _formatElapsed(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).t('voice.title'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppStrings.of(context).t('voice.subtitle'),
                style: AppTypography.body.copyWith(color: AppColors.neutral500),
              ),

              const SizedBox(height: AppSpacing.md),

              // Honest trust-level notice, matching the backend's own
              // audit-trail marking of unsigned voice reports.
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.warningContainer,
                  borderRadius: AppRadius.mdRadius,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.warning, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Requires internet — voice can\'t travel through the offline mesh. '
                        'For no-signal emergencies, use the main SOS button instead.',
                        style: AppTypography.caption.copyWith(color: AppColors.neutral900),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              Expanded(
                child: Center(
                  child: _buildStateBody(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStateBody() {
    switch (_state) {
      case _VoiceState.checking:
        return const CircularProgressIndicator();

      case _VoiceState.unavailable:
        return _buildMessageState(
          icon: Icons.mic_off,
          color: AppColors.neutral500,
          title: 'Voice SOS unavailable',
          message: _statusMessage ?? '',
          action: AppButton(label: 'Retry', onPressed: _checkAvailability),
        );

      case _VoiceState.idle:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _startRecording,
              child: Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic, size: 44, color: Colors.white),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(AppStrings.of(context).t('voice.tapToRecord'), style: AppTypography.body),
          ],
        );

      case _VoiceState.recording:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: AppColors.emergency,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.stop, size: 44, color: Colors.white),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(_formatElapsed(_elapsed), style: AppTypography.headline),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(onPressed: _cancelRecording, child: const Text('Cancel')),
                const SizedBox(width: AppSpacing.md),
                AppButton(label: 'Send', onPressed: _stopAndSend),
              ],
            ),
          ],
        );

      case _VoiceState.uploading:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.md),
            Text(_statusMessage ?? 'Sending...', style: AppTypography.body),
          ],
        );

      case _VoiceState.done:
        return _buildMessageState(
          icon: Icons.check_circle,
          color: AppColors.success,
          title: 'Voice SOS sent',
          message: _transcript != null
              ? 'Here\'s what was understood:\n"$_transcript"'
              : (_statusMessage ?? ''),
          action: AppButton(
            label: 'Record Another',
            onPressed: () => setState(() {
              _state = _VoiceState.idle;
              _transcript = null;
              _statusMessage = null;
            }),
          ),
        );

      case _VoiceState.error:
        return _buildMessageState(
          icon: Icons.error_outline,
          color: AppColors.emergency,
          title: 'Could not send',
          message: _statusMessage ?? 'Something went wrong.',
          action: AppButton(
            label: 'Try Again',
            onPressed: () => setState(() => _state = _VoiceState.idle),
          ),
        );
    }
  }

  Widget _buildMessageState({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
    required Widget action,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 56, color: color),
        const SizedBox(height: AppSpacing.md),
        Text(title, style: AppTypography.subtitle),
        const SizedBox(height: AppSpacing.sm),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppTypography.body.copyWith(color: AppColors.neutral500),
        ),
        const SizedBox(height: AppSpacing.lg),
        action,
      ],
    );
  }
}
