import 'dart:developer' as developer;

import 'package:setu_app/features/contacts/data/repositories/contact_repository.dart';
import 'package:setu_app/features/settings/data/repositories/settings_repository.dart';
import 'package:setu_app/mesh/services/identity_service.dart';
import 'package:setu_app/mesh/services/signing_service.dart';
import 'package:setu_app/services/backend_service.dart';

/// =====================================================
/// SETU Project
/// Module : Profile Sync (backend registration)
/// =====================================================
///
/// Added Aug 6 2026. WHY THIS EXISTS: the backend has had a fully
/// working server-side emergency-contact SMS notification mechanism
/// since Aug 2 (UserProfile lookup by sender_id -> notify_emergency_
/// contacts() -> real SMS Gateway) -- but the app never actually called
/// POST /register, so that lookup always found nothing and the
/// mechanism silently never fired. This is the missing link: sends
/// this device's current sender_id + name + medical info + emergency
/// contacts to the backend, over normal internet, so a packet that
/// reaches the backend via ANY relay path (not just this device's own
/// SMS attempt, which requires cellular and fails in true airplane
/// mode) still results in emergency contacts being notified.
///
/// Best-effort, fire-and-forget by design: never blocks or throws into
/// the caller's flow (profile save, contact add/edit/delete) --
/// registration failing (e.g. no internet at that exact moment) just
/// means the backend's copy is stale until the next successful sync,
/// which happens automatically the next time this is called. Since
/// POST /register now upserts (Aug 6 2026 fix), calling this
/// repeatedly is always safe.
class ProfileSyncService {
  ProfileSyncService()
      : _identityService = IdentityService(SigningService()),
        _settingsRepository = SettingsRepository(),
        _contactRepository = ContactRepository(),
        _backendService = BackendService();

  final IdentityService _identityService;
  final SettingsRepository _settingsRepository;
  final ContactRepository _contactRepository;
  final BackendService _backendService;

  /// Call this after ANY change to profile info or the contact list --
  /// see complete_profile_screen.dart and contacts_screen.dart /
  /// add_contact_screen.dart for the call sites. Safe to call
  /// unawaited (fire-and-forget) from UI code; failures are logged,
  /// never thrown.
  Future<void> syncToBackend() async {
    try {
      final senderId = await _identityService.getOrCreateSenderId();
      final settings = await _settingsRepository.getSettings();
      final contacts = await _contactRepository.getContacts();

      if (settings.userName.isEmpty) {
        // Nothing meaningful to register yet -- login hasn't completed.
        developer.log('Skipping profile sync -- no userName set yet', name: 'ProfileSyncService');
        return;
      }

      final ok = await _backendService.registerProfile(
        senderId: senderId,
        name: settings.userName,
        medicalHistory: settings.medicalNote.isNotEmpty
            ? '${settings.bloodGroup.isNotEmpty ? "Blood group: ${settings.bloodGroup}. " : ""}${settings.medicalNote}'
            : (settings.bloodGroup.isNotEmpty ? 'Blood group: ${settings.bloodGroup}' : null),
        emergencyContacts: contacts.map((c) => c.phone).toList(),
      );

      developer.log(
        ok ? 'Profile synced to backend' : 'Profile sync failed (will retry on next change)',
        name: 'ProfileSyncService',
      );
    } catch (e) {
      developer.log('Profile sync error: $e', name: 'ProfileSyncService');
    }
  }
}
