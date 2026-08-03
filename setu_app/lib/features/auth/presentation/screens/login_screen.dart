// =====================================================
// SETU Project
// Module : Login (Block 31)
// Owner  : Sudheer
// =====================================================
//
// DEMO OTP — READ BEFORE DEMOING:
// There is no real SMS gateway wired up (no backend, no
// Firebase Phone Auth project set up yet). This screen
// generates a random 6-digit code locally and shows it
// directly on screen (via the SnackBar on the next screen) so
// it's fully testable — it does NOT pretend to silently send a
// real SMS, which would be actively misleading. Swap this for
// Firebase Phone Auth or a backend OTP endpoint when one
// exists; the OTP screen's verification logic is written so
// that swap only touches _sendOtp() below, nothing else.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/app_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isSending = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);

    // DEMO OTP generation — see file header note.
    final otp = (100000 + DateTime.now().millisecondsSinceEpoch % 900000)
        .toString();

    await Future.delayed(const Duration(milliseconds: 400));

    if (!mounted) return;
    setState(() => _isSending = false);

    context.push(
      '/otp',
      extra: {
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'otp': otp,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.xl),

                Container(
                  height: 72,
                  width: 72,
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: AppRadius.lgRadius,
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    size: 38,
                    color: AppColors.primary,
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                Text('Login', style: AppTypography.headline),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Enter your name and phone number to get started.',
                  style: AppTypography.body.copyWith(
                    color: AppColors.neutral500,
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),

                Text('Full Name', style: AppTypography.subtitle),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: 'Your name'),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Name is required'
                      : null,
                ),

                const SizedBox(height: AppSpacing.md),

                Text('Mobile Number', style: AppTypography.subtitle),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    hintText: '10-digit mobile number',
                    prefixText: '+91 ',
                  ),
                  validator: (value) {
                    final digits = (value ?? '').trim();
                    if (digits.length != 10) {
                      return 'Enter a valid 10-digit number';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppSpacing.xl),

                AppButton(
                  label: _isSending ? 'Sending OTP...' : 'Send OTP',
                  onPressed: _isSending ? null : _sendOtp,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
