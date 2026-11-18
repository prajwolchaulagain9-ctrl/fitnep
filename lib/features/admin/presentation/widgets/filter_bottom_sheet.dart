import 'package:flutter/material.dart';

import '../../domain/entities/client_entity.dart';
import '../../../../app/theme/app_theme.dart';

enum FilterDimension { package, status, dietitian }

class FilterBottomSheet extends StatefulWidget {
  final FilterDimension dimension;
  final Set<String> availableOptions;
  final Set<String> selectedStrings;
  final Set<ClientStatus> selectedStatuses;
  final String title;

  const FilterBottomSheet({
    super.key,
    required this.dimension,
    required this.availableOptions,
    this.selectedStrings = const {},
    this.selectedStatuses = const {},
    required this.title,
  });

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  late Set<String> _selectedStrings;
  late Set<ClientStatus> _selectedStatuses;

  @override
  void initState() {
    super.initState();
    _selectedStrings = Set.from(widget.selectedStrings);
    _selectedStatuses = Set.from(widget.selectedStatuses);
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.availableOptions.toList()..sort();

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'Filter by ${widget.title}',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedStrings.clear();
                      _selectedStatuses.clear();
                    });
                  },
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(indent: 20, endIndent: 20),
          const SizedBox(height: 8),

          // Options
          if (widget.dimension == FilterDimension.status) ...[
            _StatusOption(
              status: ClientStatus.active,
              selected: _selectedStatuses.contains(ClientStatus.active),
              onToggle: (v) => setState(() {
                if (v) {
                  _selectedStatuses.add(ClientStatus.active);
                } else {
                  _selectedStatuses.remove(ClientStatus.active);
                }
              }),
            ),
            _StatusOption(
              status: ClientStatus.inactive,
              selected: _selectedStatuses.contains(ClientStatus.inactive),
              onToggle: (v) => setState(() {
                if (v) {
                  _selectedStatuses.add(ClientStatus.inactive);
                } else {
                  _selectedStatuses.remove(ClientStatus.inactive);
                }
              }),
            ),
          ] else ...[
            ...options.map(
              (opt) => _StringOption(
                label: opt,
                selected: _selectedStrings.contains(opt),
                onToggle: (v) => setState(() {
                  if (v) {
                    _selectedStrings.add(opt);
                  } else {
                    _selectedStrings.remove(opt);
                  }
                }),
              ),
            ),
          ],

          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop({
                    'strings': _selectedStrings,
                    'statuses': _selectedStatuses,
                  });
                },
                child: const Text('Apply'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusOption extends StatelessWidget {
  final ClientStatus status;
  final bool selected;
  final ValueChanged<bool> onToggle;

  const _StatusOption({
    required this.status,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = status == ClientStatus.active;
    final color = isActive ? AppColors.statusActive : AppColors.statusInactive;
    final label = isActive ? 'Active' : 'Inactive';

    return ListTile(
      onTap: () => onToggle(!selected),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          isActive ? Icons.check_circle_outline : Icons.block_outlined,
          color: color,
          size: 20,
        ),
      ),
      title: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: AppColors.textPrimary),
      ),
      trailing: Checkbox(
        value: selected,
        onChanged: (v) => onToggle(v ?? false),
        activeColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}

class _StringOption extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool> onToggle;

  const _StringOption({
    required this.label,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => onToggle(!selected),
      title: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: AppColors.textPrimary),
      ),
      trailing: Checkbox(
        value: selected,
        onChanged: (v) => onToggle(v ?? false),
        activeColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}
