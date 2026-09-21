import 'package:flutter/material.dart';

import '../../data/models/safety_guide_model.dart';
import '../../data/services/preparedness_service.dart';

/// Guide detail — a numbered step list, cached from the bundled asset so
/// this renders instantly and works with the phone in airplane mode.
class SafetyGuideDetailScreen extends StatelessWidget {
  const SafetyGuideDetailScreen({super.key, required this.guideId});

  final String guideId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<SafetyGuideModel?>(
        future: PreparednessService.instance.guideById(guideId),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final guide = snapshot.data;
          if (guide == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Not available')),
              body: const Center(child: Text('This guide could not be loaded.')),
            );
          }
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                title: Text(guide.title),
                floating: true,
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 13,
                            child: Text('${index + 1}', style: const TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(guide.steps[index])),
                        ],
                      ),
                    ),
                    childCount: guide.steps.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
