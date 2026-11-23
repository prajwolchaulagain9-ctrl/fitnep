import 'package:flutter/material.dart';

import '../../data/repositories/staff_account_repository.dart';
import '../../domain/entities/staff_account_entity.dart';

class StaffRecordsList<T> extends StatefulWidget {
  const StaffRecordsList({
    required this.load,
    required this.buildItem,
    required this.emptyMessage,
    super.key,
  });

  final Future<StaffPage<T>> Function(String? cursor) load;
  final Widget Function(T item) buildItem;
  final String emptyMessage;

  @override
  State<StaffRecordsList<T>> createState() => _StaffRecordsListState<T>();
}

class _StaffRecordsListState<T> extends State<StaffRecordsList<T>> {
  List<T> _items = [];
  String? _cursor;
  ({String message, bool reset})? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.load(reset ? null : _cursor);
      if (!mounted) return;
      setState(() {
        _items = [if (!reset) ..._items, ...page.items];
        _cursor = page.nextCursor;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = (
            message: error is StaffAccountFailure
                ? error.message
                : 'Could not load staff records. Try again.',
            reset: reset,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () => _load(reset: true),
    child: ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _items.length + 1,
      itemBuilder: (context, index) {
        if (index < _items.length) return widget.buildItem(_items[index]);
        if (_loading) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (_error case final failure?) {
          return Column(
            children: [
              Text(failure.message, textAlign: TextAlign.center),
              TextButton(
                onPressed: () => _load(reset: failure.reset),
                child: const Text('Try again'),
              ),
            ],
          );
        }
        if (_cursor != null) {
          return Center(
            child: TextButton(
              onPressed: () => _load(reset: false),
              child: const Text('Load more'),
            ),
          );
        }
        return _items.isEmpty
            ? Center(child: Text(widget.emptyMessage))
            : const SizedBox.shrink();
      },
    ),
  );
}
