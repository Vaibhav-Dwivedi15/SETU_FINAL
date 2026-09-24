// =====================================================
// SETU Project
// Module : Add Contact Screen (Redesign)
// =====================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';
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
        const SnackBar(
          content: Text("Contact saved successfully"),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst("Exception: ", "")),
          backgroundColor: AppColors.emergency,
        ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgApp : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text("New Emergency Contact"),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Info notice
                SetuCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  backgroundColor: isDark ? AppColors.bgSurfaceAlt : AppColors.lightSurface,
                  accentBorderLeft: AppColors.accent,
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: AppColors.accent, size: 20),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          "This contact will receive emergency text messages with your exact GPS map coordinates when you fire an SOS.",
                          style: AppTypography.caption.copyWith(
                            color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                const SetuSectionHeader(
                  title: "Contact Details",
                  subtitle: "Enter name and 10-digit mobile number",
                  padding: EdgeInsets.only(bottom: AppSpacing.sm),
                ),

                TextFormField(
                  controller: _nameController,
                  validator: Validators.validateName,
                  style: AppTypography.body.copyWith(
                    color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                  ),
                  decoration: const InputDecoration(
                    labelText: "Full Name",
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  validator: Validators.validatePhone,
                  style: AppTypography.body.copyWith(
                    color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                  ),
                  decoration: const InputDecoration(
                    labelText: "Mobile Phone Number",
                    prefixIcon: Icon(Icons.phone_outlined),
                    prefixText: "+91 ",
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),

                SetuButton(
                  label: _isSaving ? "Saving Contact..." : "SAVE EMERGENCY CONTACT",
                  icon: Icons.check_circle_outline_rounded,
                  onPressed: _isSaving ? null : _saveContact,
                  isLoading: _isSaving,
                  size: SetuButtonSize.lg,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
