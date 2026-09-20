// Aug 6 2026: deleteContact() and openAddContact()'s post-navigation
// reload now both trigger a fire-and-forget backend profile sync (see
// profile_sync_service.dart) -- contacts are exactly the data the
// backend's emergency-contact SMS notification needs, so any time the
// local list changes, the backend's copy should be refreshed too.
// POST /register upserts now (Aug 6 2026 backend fix), so calling this
// on every contact change is safe and idempotent.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/constants/app_colors.dart';
import 'package:setu_app/core/services/profile_sync_service.dart';

import '../../data/models/contact_model.dart';
import '../../data/repositories/contact_repository.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final ContactRepository _repository = ContactRepository();
  final ProfileSyncService _profileSyncService = ProfileSyncService();

  List<ContactModel> contacts = [];

  @override
  void initState() {
    super.initState();
    loadContacts();
  }

  Future<void> loadContacts() async {
    contacts = await _repository.getContacts();

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> deleteContact(int index) async {
    await _repository.deleteContact(index);
    await loadContacts();

    unawaited(_profileSyncService.syncToBackend());

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Contact deleted successfully.")),
    );
  }

  Future<void> openAddContact() async {
    final currentContacts = await _repository.getContacts();

    if (!mounted) return;

    if (currentContacts.length >= 5) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Maximum Limit Reached"),
          content: const Text(
            "You can add only 5 emergency contacts.\n\n"
            "Please delete an existing contact before adding a new one.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        ),
      );
      return;
    }

    await context.push('/add-contact');

    await loadContacts();
    // Covers the case where AddContactScreen itself doesn't sync (it
    // does too, see add_contact_screen.dart -- this is a harmless
    // redundant sync on return, not the only place it happens).
    unawaited(_profileSyncService.syncToBackend());
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.contacts_outlined, size: 90, color: Colors.grey),
        const SizedBox(height: 20),
        const Center(
          child: Text(
            "No Emergency Contacts",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              "Add up to 5 contacts who'll be notified the moment you "
              "send an SOS.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Emergency Contacts")),
      body: contacts.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.only(top: 8),
              itemCount: contacts.length,
              itemBuilder: (context, index) {
                final contact = contacts[index];

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ListTile(
                    leading: Container(
                      height: 44,
                      width: 44,
                      decoration: const BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    title: Text(
                      contact.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(contact.phone),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => deleteContact(index),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: openAddContact,
        icon: const Icon(Icons.add),
        label: const Text("Add"),
      ),
    );
  }
}
