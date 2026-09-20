// =====================================================
// SETU Project
// Module : Login (Block 31) — Email OTP
// Owner  : Sudheer
// =====================================================
//
// REPLACES THE DEMO OTP. Previously this screen generated a random
// 6-digit code locally and showed it directly on the next screen — an
// honest demo, but not real verification (see git history for the
// original header comment). Now it collects an email instead of a
// phone number and requests a real code from the backend's
// POST /auth/request-otp — see services/email_otp_service.dart and
// docs/MOBILE_BACKEND_CONTRACT.md for the full contract.
//
// WHY EMAIL, NOT SMS: SMS OTP in India needs a paid gateway plus TRAI
// DLT sender registration — this project has neither. Email is free
// with no telecom regulatory dependency. See the backend's
// app/services/email_service.py for the same reasoning written once,
// server-side.
//
// The phone number field is KEPT (not removed) — it's still used
// elsewhere (emergency contact display, profile), just no longer the
// login/verification channel.
//
// COLD-START UX: _wakingUp is kept separate from _sendError on purpose
// — a Render free-tier cold start (up to ~50s) is not an error, it's
// the server starting up. Showing it as a red error banner would look
// broken; showing it as its own informational state during the
// service's automatic 45s retry keeps the screen honest about what's
// actually happening. See services/email_otp_service.dart's
// _withColdStartRetry / onRetrying for where this is triggered from.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/app_button.dart';
import 'package:setu_app/core/language/app_strings.dart';
import 'package:setu_app/services/email_otp_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpService = EmailOtpService();
  bool _isSending = false;
  bool _wakingUp = false;
  String? _sendError;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Email is required';
    // Deliberately simple check — the backend's EmailStr does the real
    // validation and returns a clear 422 if this ever lets something
    // malformed through. This is just to catch obvious typos early.
    if (!trimmed.contains('@') || !trimmed.contains('.')) {
      return 'Enter a valid email address';
    }
    return null;
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSending = true;
      _wakingUp = false;
      _sendError = null;
    });
    final email = _emailController.text.trim();
    final result = await _otpService.requestOtp(
      email: email,
      onRetrying: () {
        if (!mounted) return;
        setState(() => _wakingUp = true);
      },
    );
    if (!mounted) return;
    setState(() {
      _isSending = false;
      _wakingUp = false;
    });
    if (!result.delivered) {
      // Honest failure: the backend accepted the request but no email
      // actually went out (SMTP not configured server-side, or the send
      // failed). Show exactly why, never a generic "code sent".
      setState(() => _sendError = result.detail);
      return;
    }
    context.push(
      '/otp',
      extra: {
        'name': _nameController.text.trim(),
        'email': email,
        'phone': _phoneController.text.trim(),
        'expiresInMinutes': result.expiresInMinutes,
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
                Text(AppStrings.of(context).t('login.title'), style: AppTypography.headline),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  AppStrings.of(context).t('login.subtitle'),
                  style: AppTypography.body.copyWith(
                    color: AppColors.neutral500,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(AppStrings.of(context).t('login.fullName'), style: AppTypography.subtitle),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: 'Your name'),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Name is required'
                      : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(AppStrings.of(context).t('login.email'), style: AppTypography.subtitle),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: 'you@example.com'),
                  validator: _validateEmail,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  AppStrings.of(context).t('login.phone'),
                  style: AppTypography.subtitle,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Used for emergency contact display — not for login.',
                  style: AppTypography.caption.copyWith(color: AppColors.neutral500),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(hintText: 'Phone number (optional)'),
                ),
                if (_wakingUp) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: AppRadius.mdRadius,
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Connecting... the server was idle and is waking up, '
                            'this can take up to 30s.',
                            style: AppTypography.caption.copyWith(color: AppColors.neutral900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_sendError != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.warningContainer,
                      borderRadius: AppRadius.mdRadius,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.warning, size: 20),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            _sendError!,
                            style: AppTypography.caption.copyWith(color: AppColors.neutral900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                AppButton(
                  label: _isSending
                      ? (_wakingUp
                          ? 'Waking up server...'
                          : AppStrings.of(context).t('login.sendingCode'))
                      : AppStrings.of(context).t('login.sendCode'),
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
