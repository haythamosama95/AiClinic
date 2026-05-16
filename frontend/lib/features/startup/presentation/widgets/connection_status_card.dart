import 'package:flutter/material.dart';

/// Surfaces deployment profile and clinic-local connectivity details on the entry screen.
class ConnectionStatusCard extends StatelessWidget {
  const ConnectionStatusCard({super.key, required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...lines.map((line) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(line))),
          ],
        ),
      ),
    );
  }
}
