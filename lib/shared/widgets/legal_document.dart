import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

typedef LegalSection = ({String id, String title, List<String> points});

class LegalDocument extends StatefulWidget {
  const LegalDocument({
    required this.path,
    required this.sections,
    this.anchor = '',
    super.key,
  });
  final String path;
  final List<LegalSection> sections;
  final String anchor;

  @override
  State<LegalDocument> createState() => _LegalDocumentState();
}

class _LegalDocumentState extends State<LegalDocument> {
  final _keys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    for (final section in widget.sections) {
      _keys[section.id] = GlobalKey();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _keys[widget.anchor]?.currentContext;
      if (mounted && target != null) Scrollable.ensureVisible(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('On this page', style: text.titleMedium),
        for (final section in widget.sections)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                context.replace('${widget.path}#${section.id}');
                final target = _keys[section.id]?.currentContext;
                if (target != null) Scrollable.ensureVisible(target);
              },
              child: Text(section.title),
            ),
          ),
        const SizedBox(height: 16),
        for (var index = 0; index < widget.sections.length; index++) ...[
          Text(
            '${index + 1}. ${widget.sections[index].title}',
            key: _keys[widget.sections[index].id],
            style: text.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final point in widget.sections[index].points)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: Text(point)),
                ],
              ),
            ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}
