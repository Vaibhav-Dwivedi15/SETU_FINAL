// =====================================================
// SETU Project
// Module : Recovery Report Form Screen (Redesign)
// =====================================================

import 'package:flutter/material.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';

import '../../data/models/recovery_report_type.dart';
import '../../data/repositories/recovery_repository.dart';

class RecoveryReportFormScreen extends StatefulWidget {
  const RecoveryReportFormScreen({super.key, required this.type});

  final RecoveryReportType type;

  @override
  State<RecoveryReportFormScreen> createState() =>
      _RecoveryReportFormScreenState();
}

class _RecoveryReportFormScreenState extends State<RecoveryReportFormScreen> {
  final _repository = RecoveryRepository();
  final _controller = TextEditingController();
  bool _sending = false;
  String? _error;

  static const int _maxMessageLength = 500;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = _controller.text.trim();
    if (message.isEmpty) {
      setState(() => _error = 'Please enter a description before transmitting.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await _repository.submitReport(type: widget.type, message: message);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.type.title} broadcasted over mesh.'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.type;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgApp : AppColors.lightBackground,
      appBar: AppBar(
        title: Text(type.title),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Type Info Banner
              SetuCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                backgroundColor: isDark ? AppColors.bgSurfaceAlt : AppColors.lightSurface,
                accentBorderLeft: AppColors.accent,
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.14),
                        borderRadius: AppRadius.smRadius,
                      ),
                      child: Icon(type.icon, color: AppColors.accent, size: 22),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            type.title,
                            style: AppTypography.cardTitle.copyWith(
                              color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            type.subtitle,
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
                title: 'Incident Details',
                subtitle: 'Include specific location identifiers, needs, or damage scale',
                padding: EdgeInsets.only(bottom: AppSpacing.sm),
              ),

              TextField(
                controller: _controller,
                maxLength: _maxMessageLength,
                maxLines: 6,
                style: AppTypography.body.copyWith(
                  color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Describe details of ${type.title.toLowerCase()}...',
                  hintStyle: AppTypography.body.copyWith(
                    color: isDark ? AppColors.textDim : AppColors.lightTextDim,
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.emergencyContainer : const Color(0xFFFEE2E2),
                    borderRadius: AppRadius.smRadius,
                    border: Border.all(color: AppColors.emergency.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.emergency, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: AppTypography.caption.copyWith(
                            color: isDark ? AppColors.textPrimary : AppColors.emergency,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: AppSpacing.md),

              // Metadata attached banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.bgSurface : AppColors.lightSurface,
                  borderRadius: AppRadius.smRadius,
                  border: Border.all(
                    color: isDark ? AppColors.borderSubtle : AppColors.lightBorder,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.my_location_rounded,
                      size: 16,
                      color: isDark ? AppColors.textDim : AppColors.lightTextDim,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Device GPS coordinates and timestamp will be attached automatically.',
                        style: AppTypography.caption.copyWith(
                          color: isDark ? AppColors.textDim : AppColors.lightTextDim,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              SetuButton(
                label: _sending ? 'Broadcasting...' : 'TRANSMIT REPORT TO MESH',
                icon: Icons.send_rounded,
                onPressed: _sending ? null : _submit,
                isLoading: _sending,
                size: SetuButtonSize.lg,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
