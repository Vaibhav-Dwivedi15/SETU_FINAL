import '../models/contact_model.dart';
import '../services/contact_service.dart';

class ContactRepository {
  final ContactService _service = ContactService();

  Future<List<ContactModel>> getContacts() {
    return _service.getContacts();
  }

  Future<void> saveContacts(List<ContactModel> contacts) {
    return _service.saveContacts(contacts);
  }

  Future<void> addContact(ContactModel contact) async {
    final contacts = await getContacts();

    if (contacts.length >= 5) {
      throw Exception('Maximum 5 emergency contacts allowed.');
    }

    contacts.add(contact);

    await saveContacts(contacts);
  }

  Future<void> deleteContact(int index) async {
    final contacts = await getContacts();

    if (index >= 0 && index < contacts.length) {
      contacts.removeAt(index);
      await saveContacts(contacts);
    }
  }
}
