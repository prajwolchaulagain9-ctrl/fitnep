import 'package:flutter/material.dart';

class IntakePriorityCard extends StatelessWidget {
  const IntakePriorityCard({
    super.key,
    required this.title,
    required this.values,
    required this.icon,
    required this.color,
  });

  final String title;
  final List<String> values;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: color, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (values.isEmpty)
            const Text('None reported')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: values
                  .map(
                    (value) => Chip(
                      label: Text(value),
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      side: BorderSide(color: color.withValues(alpha: 0.4)),
                    ),
                  )
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }
}
