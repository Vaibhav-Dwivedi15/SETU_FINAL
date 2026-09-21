import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/safety_guide_model.dart';
import '../../data/services/preparedness_service.dart';

/// BEFORE-disaster hub: offline safety guides + a link to the device
/// readiness check. Minimal UI on purpose (session brief: functional
/// engineering over cosmetics) -- plain Material widgets, no new design
/// system component, list + detail is enough for what this needs to do.
class PreparednessScreen extends StatefulWidget {
  const PreparednessScreen({super.key});

  @override
  State<PreparednessScreen> createState() => _PreparednessScreenState();
}

class _PreparednessScreenState extends State<PreparednessScreen> {
  late final Future<List<SafetyGuideModel>> _guides;

  @override
  void initState() {
    super.initState();
    _guides = PreparednessService.instance.loadGuides();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Preparedness')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.checklist_rtl),
                title: const Text('Device readiness check'),
                subtitle: const Text('Bluetooth, location, Wi-Fi and mesh status'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/preparedness/readiness'),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Safety guides — work without internet',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<SafetyGuideModel>>(
              future: _guides,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final guides = snapshot.data ?? const [];
                if (guides.isEmpty) {
                  return const Center(child: Text('Safety guides unavailable on this build.'));
                }
                return ListView.builder(
                  itemCount: guides.length,
                  itemBuilder: (context, index) {
                    final guide = guides[index];
                    return ListTile(
                      leading: _iconFor(guide.id),
                      title: Text(guide.title),
                      subtitle: Text(guide.summary),
                      onTap: () => context.push('/preparedness/guide/${guide.id}'),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Icon _iconFor(String id) {
    switch (id) {
      case 'flood':
        return const Icon(Icons.water);
      case 'fire':
        return const Icon(Icons.local_fire_department);
      case 'earthquake':
        return const Icon(Icons.vibration);
      case 'accident':
        return const Icon(Icons.emergency);
      case 'women_safety':
        return const Icon(Icons.shield);
      case 'child_safety':
        return const Icon(Icons.child_care);
      case 'senior_citizen':
        return const Icon(Icons.elderly);
      default:
        return const Icon(Icons.info_outline);
    }
  }
}
