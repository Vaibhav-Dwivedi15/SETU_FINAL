import 'package:flutter/material.dart';

import 'package:setu_app/core/widgets/hub_tile.dart';

import '../../data/models/safety_guide_model.dart';

/// A guide row for the disaster-guide and recovery-guidance lists.
class GuideListTile extends StatelessWidget {
  const GuideListTile({super.key, required this.guide, required this.icon, required this.onTap});

  final SafetyGuideModel guide;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      HubTile(icon: icon, title: guide.title, subtitle: guide.summary, onTap: onTap);
}
