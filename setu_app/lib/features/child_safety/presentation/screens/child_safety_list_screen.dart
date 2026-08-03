// =====================================================
// SETU Project
// Module : Child Safety Mode (UI + local storage only)
// Owner  : Sudheer
// =====================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/constants/app_colors.dart';

import '../../data/models/child_profile_model.dart';
import '../../data/repositories/child_safety_repository.dart';

class ChildSafetyListScreen extends StatefulWidget {
  const ChildSafetyListScreen({super.key});

  @override
  State<ChildSafetyListScreen> createState() => _ChildSafetyListScreenState();
}

class _ChildSafetyListScreenState extends State<ChildSafetyListScreen> {
  final ChildSafetyRepository _repository = ChildSafetyRepository();

  List<ChildProfileModel> profiles = [];

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    profiles = await _repository.getProfiles();

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _deleteProfile(String id) async {
    await _repository.deleteProfile(id);
    await _loadProfiles();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile deleted successfully.')),
    );
  }

  Future<void> _openAddProfile() async {
    await context.push('/child-safety/add');
    await _loadProfiles();
  }

  Future<void> _openEditProfile(ChildProfileModel profile) async {
    await context.push('/child-safety/edit', extra: profile);
    await _loadProfiles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Child Safety Profiles')),
      body: profiles.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.child_care,
                      size: 80,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'No Child Safety Profiles',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Add a profile with guardian, medical, and safe-location '
                      'details to speed up response if a child ever goes missing.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              itemCount: profiles.length,
              itemBuilder: (context, index) {
                final profile = profiles[index];

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: Container(
                      height: 44,
                      width: 44,
                      decoration: const BoxDecoration(
                        gradient: AppColors.infoGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.child_care,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    title: Text(
                      profile.childName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Age ${profile.childAge} · Guardian: ${profile.guardianName}',
                    ),
                    onTap: () => _openEditProfile(profile),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteProfile(profile.id),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddProfile,
        icon: const Icon(Icons.add),
        label: const Text('Add Profile'),
      ),
    );
  }
}
