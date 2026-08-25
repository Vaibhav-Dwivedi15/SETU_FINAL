// =====================================================
// SETU Project
// Module : OTP Verification (Block 31) — Email OTP
// Owner  : Sudheer
// =====================================================
//
// REPLACES THE DEMO OTP. Previously the correct code was passed in and
// compared locally — now this screen calls the backend's real
// POST /auth/verify-otp and shows whatever specific failure reason it
// returns (expired / too many attempts / incorrect / no active code),
// rather than one generic error. See services/email_otp_service.dart.
//
// Resend uses the same POST /auth/request-otp the login screen calls.
// The backend enforces its own 60-second resend cooldown server-side
// (reuses the existing live code rather than emailing a new one within
// that window) — this screen's local 30s button-disable timer is just
// UX pacing on top of that, not a substitute for it.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/app_button.dart';
import 'package:setu_app/features/settings/data/repositories/settings_repository.dart';
import 'package:setu_app/core/language/app_strings.dart';
import 'package:setu_app/services/email_otp_service.dart';

class OtpScreen extends StatefulWidget {
  final String name;
  final String email;
  final String phone;
  final int expiresInMinutes;

  const OtpScreen({
    super.key,
    required this.name,
    required this.email,
    required this.phone,
    this.expiresInMinutes = 10,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _controller = TextEditingController();
  final _settingsRepository = SettingsRepository();
  final _otpService = EmailOtpService();

  String? _error;
  bool _isVerifying = false;
  bool _isResending = false;
  String? _resendMessage;

  int _resendCooldown = 30;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _controller.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = 30);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldown <= 1) {
        timer.cancel();
        setState(() => _resendCooldown = 0);
        return;
      }
      setState(() => _resendCooldown -= 1);
    });
  }

  Future<void> _verify() async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the code sent to your email.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _error = null;
    });

    final result = await _otpService.verifyOtp(email: widget.email, code: code);

    if (!mounted) return;

    if (!result.verified) {
      setState(() {
        _isVerifying = false;
        _error = result.detail;
      });
      return;
    }

    final settings = await _settingsRepository.getSettings();
    await _settingsRepository.saveSettings(
      settings.copyWith(userName: widget.name, phoneNumber: widget.phone),
    );

    if (!mounted) return;
    context.go('/complete-profile');
  }

  Future<void> _resend() async {
    if (_resendCooldown > 0 || _isResending) return;

    setState(() {
      _isResending = true;
      _resendMessage = null;
      _error = null;
    });

    final result = await _otpService.requestOtp(email: widget.email);

    if (!mounted) return;
    setState(() {
      _isResending = false;
      _resendMessage = result.delivered
          ? 'A new code was sent to ${widget.email}.'
          : result.detail;
    });

    if (result.delivered) {
      _startCooldown();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).t('otp.title'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter the ${widget.expiresInMinutes}-minute code sent to ${widget.email}',
                style: AppTypography.body.copyWith(color: AppColors.neutral500),
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

              const SizedBox(height: AppSpacing.md),

              if (_resendMessage != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: AppRadius.mdRadius,
                  ),
                  child: Text(
                    _resendMessage!,
                    style: AppTypography.caption.copyWith(color: AppColors.neutral900),
                  ),
                ),

              const SizedBox(height: AppSpacing.lg),

              AppButton(
                label: _isVerifying
                    ? AppStrings.of(context).t('otp.verifying')
                    : AppStrings.of(context).t('otp.verify'),
                onPressed: _isVerifying ? null : _verify,
              ),

              const SizedBox(height: AppSpacing.md),

              Center(
                child: TextButton(
                  onPressed: (_resendCooldown > 0 || _isResending) ? null : _resend,
                  child: Text(
                    _isResending
                        ? 'Sending...'
                        : _resendCooldown > 0
                            ? '${AppStrings.of(context).t('otp.resend')} (${_resendCooldown}s)'
                            : AppStrings.of(context).t('otp.resend'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
