import 'package:setu_app/features/contacts/data/services/contact_service.dart';

import '../models/emergency_contact.dart';
import 'emergency_plan_repository.dart';

/// Assembles the Emergency Contacts list from what the user has already
/// entered elsewhere in SETU: the emergency plan's two contacts and the
/// saved SOS contacts. Nothing is bundled or invented -- SETU ships no
/// official government numbers.
class EmergencyContactsRepository {
  EmergencyContactsRepository({
    EmergencyPlanRepository? planRepository,
    ContactService? contactService,
  })  : _plans = planRepository ?? EmergencyPlanRepository(),
        _contacts = contactService ?? ContactService();

  final EmergencyPlanRepository _plans;
  final ContactService _contacts;

  Future<List<EmergencyContact>> load() async {
    final plan = await _plans.load();
    final result = <EmergencyContact>[];

    void addPlanContact(String name, String phone, String purpose) {
      if (phone.trim().isEmpty) return;
      result.add(EmergencyContact(
        name: name.trim().isEmpty ? purpose : name.trim(),
        purpose: purpose,
        phone: phone.trim(),
        source: EmergencyContactSource.plan,
      ));
    }

    addPlanContact(plan.primaryName, plan.primaryPhone, 'Primary emergency contact');
    addPlanContact(plan.secondaryName, plan.secondaryPhone, 'Secondary emergency contact');

    for (final saved in await _contacts.getContacts()) {
      final alreadyListed = result.any((c) => _sameNumber(c.phone, saved.phone));
      if (alreadyListed) continue;
      result.add(EmergencyContact(
        name: saved.name,
        purpose: 'Notified when you send an SOS',
        phone: saved.phone,
        source: EmergencyContactSource.saved,
      ));
    }
    return result;
  }

  static bool _sameNumber(String a, String b) {
    final da = a.replaceAll(RegExp(r'\D'), '');
    final db = b.replaceAll(RegExp(r'\D'), '');
    if (da.isEmpty || db.isEmpty) return false;
    return da.endsWith(db) || db.endsWith(da);
  }
}
