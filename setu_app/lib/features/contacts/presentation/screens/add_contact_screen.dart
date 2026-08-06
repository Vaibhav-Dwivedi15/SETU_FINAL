// Aug 6 2026: _saveContact() now also triggers a fire-and-forget
// backend profile sync after a successful local save -- see
// profile_sync_service.dart and contacts_screen.dart's matching
// comment for the full reasoning.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:setu_app/core/services/profile_sync_service.dart';
import '../../../../core/utils/validators.dart';
import '../../data/models/contact_model.dart';
import '../../data/repositories/contact_repository.dart';
class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});
  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}
class _AddContactScreenState extends State<AddContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final ContactRepository _repository = ContactRepository();
  final ProfileSyncService _profileSyncService = ProfileSyncService();
  bool _isSaving = false;
  Future<void> _saveContact() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      await _repository.addContact(
        ContactModel(
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
        ),
      );

      unawaited(_profileSyncService.syncToBackend());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Contact saved successfully")),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Emergency Contact")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                validator: Validators.validateName,
                decoration: const InputDecoration(
                  labelText: "Contact Name",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                validator: Validators.validatePhone,
                decoration: const InputDecoration(
                  labelText: "Phone Number",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveContact,
                  child: Text(_isSaving ? "Saving..." : "Save Contact"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
