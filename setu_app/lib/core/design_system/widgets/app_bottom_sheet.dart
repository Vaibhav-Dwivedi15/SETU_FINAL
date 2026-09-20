// =====================================================
// SETU Design System v1.0
// Module : Bottom Sheet
// Owner  : Sudheer
// =====================================================
//
// Use this instead of showDialog/AlertDialog for anything
// that's a set of actions or a form — bottom sheets read as
// more modern and are easier to reach one-handed than a
// centered dialog.

import 'package:flutter/material.dart';

import '../app_radius.dart';
import '../app_spacing.dart';

class AppBottomSheet {
  AppBottomSheet._();

  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    bool isScrollControlled = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.md,
            right: AppSpacing.md,
            top: AppSpacing.sm,
            bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: AppRadius.pillRadius,
                  ),
                ),
                child,
              ],
            ),
          ),
        );
      },
    );
  }
}
