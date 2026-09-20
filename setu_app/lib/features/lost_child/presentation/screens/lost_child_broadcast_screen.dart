// =====================================================
// SETU Project
// Module : Lost Child Alert (UI-only)
// Owner  : Sudheer
// =====================================================
//
// PHASE 1 SCOPE NOTE:
// "Broadcast" is a stub — it shows a preview dialog of what
// would be sent, it does NOT actually transmit anything.
// Real broadcast requires a new packet type through the mesh
// layer (Phase 2 — see lost_child_alert_model.dart header).

import 'package:flutter/material.dart';

import 'package:setu_app/core/constants/app_colors.dart';
import 'package:setu_app/features/child_safety/data/models/child_profile_model.dart';
import 'package:setu_app/features/child_safety/data/repositories/child_safety_repository.dart';

import '../../data/models/lost_child_alert_model.dart';
import '../widgets/lost_child_alert_card.dart';

class LostChildBroadcastScreen extends StatefulWidget {
  const LostChildBroadcastScreen({super.key});

  @override
  State<LostChildBroadcastScreen> createState() =>
      _LostChildBroadcastScreenState();
}

class _LostChildBroadcastScreenState extends State<LostChildBroadcastScreen> {
  final _formKey = GlobalKey<FormState>();
  final ChildSafetyRepository _childSafetyRepository = ChildSafetyRepository();

  final _childNameController = TextEditingController();
  final _ageController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _lastSeenLocationController = TextEditingController();
  final _guardianContactController = TextEditingController();

  List<ChildProfileModel> _savedProfiles = [];
  ChildProfileModel? _selectedProfile;

  @override
  void initState() {
    super.initState();
    _loadSavedProfiles();
  }

  Future<void> _loadSavedProfiles() async {
    final profiles = await _childSafetyRepository.getProfiles();
    if (!mounted) return;
    setState(() {
      _savedProfiles = profiles;
    });
  }

  void _prefillFromProfile(ChildProfileModel? profile) {
    setState(() {
      _selectedProfile = profile;
    });

    if (profile == null) return;

    _childNameController.text = profile.childName;
    _ageController.text = profile.childAge.toString();
    _guardianContactController.text = profile.guardianPhone;
    _lastSeenLocationController.text = profile.homeAddress;
  }

  @override
  void dispose() {
    _childNameController.dispose();
    _ageController.dispose();
    _descriptionController.dispose();
    _lastSeenLocationController.dispose();
    _guardianContactController.dispose();
    super.dispose();
  }

  void _previewBroadcast() {
    if (!_formKey.currentState!.validate()) return;

    final alert = LostChildAlertModel(
      childName: _childNameController.text.trim(),
      age: int.tryParse(_ageController.text.trim()) ?? 0,
      description: _descriptionController.text.trim(),
      lastSeenLocation: _lastSeenLocationController.text.trim(),
      lastSeenTime: DateTime.now(),
      guardianContact: _guardianContactController.text.trim(),
    );

    showDialog(
      context: context,
      builder: (_) => LostChildAlertCard(
        alert: alert,
        onSighted: () => Navigator.pop(context),
        onNotSeen: () => Navigator.pop(context),
      ),
    ).then((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Preview only — actual broadcast needs mesh packet '
            'support (Phase 2, not built yet).',
          ),
        ),
      );
    });
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    int maxLines = 1,
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
        validator: (value) =>
            (value == null || value.trim().isEmpty) ? '$label is required' : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compose Lost Child Alert')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              if (_savedProfiles.isNotEmpty) ...[
                const Text(
                  'Prefill from a saved profile (optional)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<ChildProfileModel>(
                  initialValue: _selectedProfile,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  hint: const Text('Select a child profile'),
                  items: _savedProfiles
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(p.childName),
                        ),
                      )
                      .toList(),
                  onChanged: _prefillFromProfile,
                ),
                const SizedBox(height: 20),
              ],

              _field(_childNameController, 'Child Name'),
              _field(_ageController, 'Age', keyboardType: TextInputType.number),
              _field(
                _descriptionController,
                'Description (clothing, appearance, marks)',
                maxLines: 3,
              ),
              _field(_lastSeenLocationController, 'Last Seen Location'),
              _field(
                _guardianContactController,
                'Guardian Contact',
                keyboardType: TextInputType.phone,
              ),

              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.alert,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _previewBroadcast,
                  child: const Text('Preview Broadcast'),
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
