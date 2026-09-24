// =====================================================
// SETU Project
// Module : Contacts Screen (Redesign)
// =====================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';
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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    loadContacts();
  }

  Future<void> loadContacts() async {
    final list = await _repository.getContacts();
    if (mounted) {
      setState(() {
        contacts = list;
        _isLoading = false;
      });
    }
  }

  Future<void> deleteContact(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Contact"),
        content: Text("Remove ${contacts[index].name} from emergency broadcast list?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.emergency),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

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
            "You can configure up to 5 emergency contacts.\n\n"
            "Please remove an existing contact before adding a new one.",
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
    unawaited(_profileSyncService.syncToBackend());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgApp : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text("Emergency Contacts"),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: openAddContact,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text("Add Contact"),
        backgroundColor: isDark ? AppColors.accent : AppColors.primary,
        foregroundColor: isDark ? AppColors.bgApp : Colors.white,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : contacts.isEmpty
                ? SetuEmptyState(
                    icon: Icons.contacts_outlined,
                    title: "No Emergency Contacts",
                    description:
                        "Add up to 5 trusted contacts who will immediately receive SMS notifications with your live GPS location when you fire SOS.",
                    actionLabel: "Add Contact Now",
                    onAction: openAddContact,
                  )
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      // Information banner
                      SetuCard(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        backgroundColor: isDark ? AppColors.bgSurfaceAlt : AppColors.lightSurface,
                        accentBorderLeft: AppColors.accent,
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.14),
                                borderRadius: AppRadius.smRadius,
                              ),
                              child: const Icon(Icons.shield_outlined, color: AppColors.accent, size: 20),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        "Automated SMS Broadcast",
                                        style: AppTypography.cardTitle.copyWith(
                                          color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        "${contacts.length} / 5",
                                        style: AppTypography.metadata.copyWith(
                                          color: AppColors.accent,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "When SOS is fired, encrypted packets and SMS alerts are dispatched to this list.",
                                    style: AppTypography.caption.copyWith(
                                      color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: AppSpacing.lg),

                      const SetuSectionHeader(
                        title: "Configured Contacts",
                        subtitle: "Notified on private and public SOS",
                        padding: EdgeInsets.only(bottom: AppSpacing.sm),
                      ),

                      ...contacts.asMap().entries.map((entry) {
                        final index = entry.key;
                        final contact = entry.value;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: SetuCard(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isDark ? AppColors.bgInput : AppColors.lightBackground,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isDark ? AppColors.borderSubtle : AppColors.lightBorder,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.person_rounded,
                                    size: 20,
                                    color: AppColors.accent,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        contact.name,
                                        style: AppTypography.cardTitle.copyWith(
                                          color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                                          fontSize: 14.5,
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        contact.phone,
                                        style: AppTypography.caption.copyWith(
                                          color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: AppColors.emergency,
                                    size: 20,
                                  ),
                                  tooltip: "Delete Contact",
                                  onPressed: () => deleteContact(index),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 80), // Room for FAB
                    ],
                  ),
      ),
    );
  }
}
