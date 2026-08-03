import '../models/settings_model.dart';
import '../services/settings_service.dart';

class SettingsRepository {
  final SettingsService _service = SettingsService();

  Future<SettingsModel> getSettings() {
    return _service.loadSettings();
  }

  Future<void> saveSettings(SettingsModel settings) {
    return _service.saveSettings(settings);
  }

  Future<void> resetSettings() {
    return _service.resetSettings();
  }
}
