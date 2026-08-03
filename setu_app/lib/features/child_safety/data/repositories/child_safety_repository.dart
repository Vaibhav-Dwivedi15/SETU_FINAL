// =====================================================
// SETU Project
// Module : Child Safety Mode (UI + local storage only)
// Owner  : Sudheer
// =====================================================

import '../models/child_profile_model.dart';
import '../services/child_safety_service.dart';

class ChildSafetyRepository {
  final ChildSafetyService _service = ChildSafetyService();

  Future<List<ChildProfileModel>> getProfiles() {
    return _service.getProfiles();
  }

  Future<void> addProfile(ChildProfileModel profile) async {
    final profiles = await getProfiles();
    profiles.add(profile);
    await _service.saveProfiles(profiles);
  }

  Future<void> updateProfile(ChildProfileModel profile) async {
    final profiles = await getProfiles();
    final index = profiles.indexWhere((p) => p.id == profile.id);

    if (index != -1) {
      profiles[index] = profile;
      await _service.saveProfiles(profiles);
    }
  }

  Future<void> deleteProfile(String id) async {
    final profiles = await getProfiles();
    profiles.removeWhere((p) => p.id == id);
    await _service.saveProfiles(profiles);
  }
}
