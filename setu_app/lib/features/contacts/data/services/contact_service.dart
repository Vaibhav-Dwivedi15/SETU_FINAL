import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/contact_model.dart';

class ContactService {
  static const String _storageKey = 'emergency_contacts';

  Future<List<ContactModel>> getContacts() async {
    final prefs = await SharedPreferences.getInstance();

    final jsonString = prefs.getString(_storageKey);

    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    final List<dynamic> decoded = jsonDecode(jsonString);

    return decoded
        .map((e) => ContactModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveContacts(List<ContactModel> contacts) async {
    final prefs = await SharedPreferences.getInstance();

    final jsonString = jsonEncode(contacts.map((e) => e.toJson()).toList());

    await prefs.setString(_storageKey, jsonString);
  }
}
