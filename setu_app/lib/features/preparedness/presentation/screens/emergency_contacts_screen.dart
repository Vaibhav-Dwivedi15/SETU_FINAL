import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';
import 'package:setu_app/core/widgets/theme_colors.dart';

import '../../data/models/emergency_contact.dart';
import '../../data/repositories/emergency_contacts_repository.dart';

/// Opens the phone dialer for a contact. Injectable so tests never touch
/// the platform. Returns whether the OS accepted the request.
typedef DialLauncher = Future<bool> Function(Uri uri);

Future<bool> _launchDialer(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// The contacts the user has entered: the plan's primary/secondary
/// contacts and their saved SOS contacts. SETU bundles no official
/// government numbers, and says so on this screen.
class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key, this.repository, this.dialLauncher = _launchDialer});

  final EmergencyContactsRepository? repository;
  final DialLauncher dialLauncher;

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  late final EmergencyContactsRepository _repository =
      widget.repository ?? EmergencyContactsRepository();
  late Future<List<EmergencyContact>> _contacts = _repository.load();

  Future<void> _call(EmergencyContact contact) async {
    final uri = contact.dialUri;
    var opened = false;
    if (uri != null) {
      try {
        opened = await widget.dialLauncher(uri);
      } catch (_) {
        opened = false;
      }
    }
    if (!mounted) return;
    // Only claim what actually happened: the dialer opening is all we know.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(opened
          ? 'Opening the phone app for ${contact.name}.'
          : 'Could not open the phone app. Number: ${contact.phone}'),
    ));
  }

  Future<void> _go(String route) async {
    await context.push<Object?>(route);
    if (mounted) {
      setState(() {
        _contacts = _repository.load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.screenBackground,
      appBar: AppBar(title: const Text('Emergency contacts'), centerTitle: true),
      body: SafeArea(
        child: FutureBuilder<List<EmergencyContact>>(
          future: _contacts,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final contacts = snapshot.data ?? const [];
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(
                  'These are contacts you saved. SETU does not include official '
                  'emergency numbers; use the ones for your area.',
                  style: AppTypography.caption.copyWith(color: context.textSecondaryColor),
                ),
                const SizedBox(height: AppSpacing.md),
                if (contacts.isEmpty)
                  SetuEmptyState(
                    icon: Icons.contact_phone_outlined,
                    title: 'No emergency contacts yet',
                    description: 'Add contacts to your emergency plan or SOS contacts.',
                    actionLabel: 'Open emergency plan',
                    onAction: () => _go('/preparedness/plan'),
                  ),
                for (final contact in contacts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: SetuCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(contact.name,
                                    style: AppTypography.cardTitle
                                        .copyWith(color: context.textPrimaryColor)),
                                Text(contact.purpose,
                                    style: AppTypography.caption
                                        .copyWith(color: context.textSecondaryColor)),
                                Text(contact.phone,
                                    style: AppTypography.body
                                        .copyWith(color: context.textPrimaryColor)),
                              ],
                            ),
                          ),
                          IconButton.filled(
                            tooltip: 'Call ${contact.name}',
                            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                            style: IconButton.styleFrom(backgroundColor: AppColors.success),
                            icon: const Icon(Icons.call_rounded),
                            onPressed: () => _call(contact),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                SetuButton(
                  label: 'Edit emergency plan',
                  icon: Icons.edit_rounded,
                  variant: SetuButtonVariant.outlined,
                  onPressed: () => _go('/preparedness/plan'),
                ),
                const SizedBox(height: AppSpacing.sm),
                SetuButton(
                  label: 'Manage SOS contacts',
                  icon: Icons.contacts_rounded,
                  variant: SetuButtonVariant.outlined,
                  onPressed: () => _go('/contacts'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
