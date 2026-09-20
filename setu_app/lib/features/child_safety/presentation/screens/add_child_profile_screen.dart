// =====================================================
// SETU Project
// Module : Child Safety Mode (UI + local storage only)
// Owner  : Sudheer
// =====================================================

import 'package:flutter/material.dart';

import '../../data/models/child_profile_model.dart';
import '../../data/repositories/child_safety_repository.dart';

class AddChildProfileScreen extends StatefulWidget {
  final ChildProfileModel? existingProfile;

  const AddChildProfileScreen({super.key, this.existingProfile});

  @override
  State<AddChildProfileScreen> createState() => _AddChildProfileScreenState();
}

class _AddChildProfileScreenState extends State<AddChildProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final ChildSafetyRepository _repository = ChildSafetyRepository();

  late final TextEditingController _childNameController;
  late final TextEditingController _childAgeController;
  late final TextEditingController _childIdController;
  late final TextEditingController _guardianNameController;
  late final TextEditingController _guardianRelationController;
  late final TextEditingController _guardianPhoneController;
  late final TextEditingController _medicalInfoController;
  late final TextEditingController _homeAddressController;
  late final TextEditingController _schoolAddressController;

  bool _isSaving = false;

  bool get _isEditing => widget.existingProfile != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existingProfile;

    _childNameController = TextEditingController(text: p?.childName ?? '');
    _childAgeController = TextEditingController(
      text: p != null ? p.childAge.toString() : '',
    );
    _childIdController = TextEditingController(text: p?.childIdNumber ?? '');
    _guardianNameController = TextEditingController(text: p?.guardianName ?? '');
    _guardianRelationController = TextEditingController(
      text: p?.guardianRelation ?? '',
    );
    _guardianPhoneController = TextEditingController(text: p?.guardianPhone ?? '');
    _medicalInfoController = TextEditingController(text: p?.medicalInfo ?? '');
    _homeAddressController = TextEditingController(text: p?.homeAddress ?? '');
    _schoolAddressController = TextEditingController(text: p?.schoolAddress ?? '');
  }

  @override
  void dispose() {
    _childNameController.dispose();
    _childAgeController.dispose();
    _childIdController.dispose();
    _guardianNameController.dispose();
    _guardianRelationController.dispose();
    _guardianPhoneController.dispose();
    _medicalInfoController.dispose();
    _homeAddressController.dispose();
    _schoolAddressController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final profile = ChildProfileModel(
      id: widget.existingProfile?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      childName: _childNameController.text.trim(),
      childAge: int.tryParse(_childAgeController.text.trim()) ?? 0,
      childIdNumber: _childIdController.text.trim(),
      guardianName: _guardianNameController.text.trim(),
      guardianRelation: _guardianRelationController.text.trim(),
      guardianPhone: _guardianPhoneController.text.trim(),
      medicalInfo: _medicalInfoController.text.trim(),
      homeAddress: _homeAddressController.text.trim(),
      schoolAddress: _schoolAddressController.text.trim(),
    );

    try {
      if (_isEditing) {
        await _repository.updateProfile(profile);
      } else {
        await _repository.addProfile(profile);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing ? 'Profile updated' : 'Profile saved'),
        ),
      );

      Navigator.pop(context);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    int maxLines = 1,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: required
            ? (value) =>
                (value == null || value.trim().isEmpty) ? '$label is required' : null
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Child Profile' : 'Add Child Profile'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              _sectionTitle('Child Information'),
              _field(_childNameController, 'Child Name', required: true),
              _field(
                _childAgeController,
                'Age',
                keyboardType: TextInputType.number,
                required: true,
              ),
              _field(_childIdController, 'Child ID (school ID, etc.)'),

              _sectionTitle('Guardian Registration'),
              _field(_guardianNameController, 'Guardian Name', required: true),
              _field(_guardianRelationController, 'Relation (e.g. Mother, Father)'),
              _field(
                _guardianPhoneController,
                'Guardian Phone',
                keyboardType: TextInputType.phone,
                required: true,
              ),

              _sectionTitle('Medical Information'),
              _field(
                _medicalInfoController,
                'Allergies, conditions, blood group, etc.',
                maxLines: 3,
              ),

              _sectionTitle('Safe Home / School Location'),
              _field(_homeAddressController, 'Home Address', maxLines: 2),
              _field(_schoolAddressController, 'School Address', maxLines: 2),

              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveProfile,
                  child: Text(_isSaving ? 'Saving...' : 'Save Profile'),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
