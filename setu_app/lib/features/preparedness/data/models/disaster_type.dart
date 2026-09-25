import 'package:flutter/material.dart';

/// Disasters SETU ships a structured Before/During/After/Avoid guide for.
///
/// The enum is only a typed handle for icon/ordering: the guide content
/// itself lives in assets/preparedness/safety_guides.json, keyed by
/// [id], so a new disaster type is a JSON entry plus (optionally) one
/// enum value here for its icon -- no screen changes.
enum DisasterType {
  flood('flood', Icons.water_rounded),
  earthquake('earthquake', Icons.vibration_rounded),
  cyclone('cyclone', Icons.cyclone_rounded),
  fire('fire', Icons.local_fire_department_rounded),
  landslide('landslide', Icons.landslide_rounded);

  const DisasterType(this.id, this.icon);

  final String id;
  final IconData icon;

  static DisasterType? fromId(String id) {
    for (final type in DisasterType.values) {
      if (type.id == id) return type;
    }
    return null;
  }
}
