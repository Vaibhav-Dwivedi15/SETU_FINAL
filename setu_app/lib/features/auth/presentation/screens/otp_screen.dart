// =====================================================
// SETU Project
// Module : OTP Verification (Block 31)
// Owner  : Sudheer
// =====================================================
//
// See login_screen.dart header for why this is a DEMO OTP —
// the code is shown directly on this screen (in a banner) so
// it's testable without real SMS. Swap to real verification
// later by replacing _verify()'s comparison with a backend/
// Firebase call — the rest of this screen doesn't need to
// change.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/app_button.dart';
import 'package:setu_app/features/settings/data/repositories/settings_repository.dart';

class OtpScreen extends StatefulWidget {
  final String name;
  final String phone;
  final String otp;

  const OtpScreen({
    super.key,
    required this.name,
    required this.phone,
    required this.otp,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _controller = TextEditingController();
  final _settingsRepository = SettingsRepository();

  String? _error;
  bool _isVerifying = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_controller.text.trim() != widget.otp) {
      setState(() => _error = 'Incorrect code. Try again.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _error = null;
    });

    final settings = await _settingsRepository.getSettings();
    await _settingsRepository.saveSettings(
      settings.copyWith(userName: widget.name, phoneNumber: widget.phone),
    );

    if (!mounted) return;
    context.go('/complete-profile');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify OTP')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter the 6-digit code sent to +91 ${widget.phone}',
                style: AppTypography.body.copyWith(color: AppColors.neutral500),
              ),

              const SizedBox(height: AppSpacing.md),

              // DEMO MODE BANNER — remove once real SMS/Firebase
              // verification is wired up.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.warningContainer,
                  borderRadius: AppRadius.mdRadius,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.warning, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Demo mode — no SMS was actually sent. Your code is: ${widget.otp}',
                        style: AppTypography.caption,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: AppTypography.headline,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '000000',
                  errorText: _error,
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              AppButton(
                label: _isVerifying ? 'Verifying...' : 'Verify & Continue',
                onPressed: _isVerifying ? null : _verify,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
