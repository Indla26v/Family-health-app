import 'package:flutter/material.dart';

import '../../core/theme.dart';

class PillMenu<T> extends StatelessWidget {
  const PillMenu({
    super.key,
    required this.label,
    required this.icon,
    required this.options,
    required this.value,
    required this.onSelected,
  });
  final String label;
  final IconData icon;
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final current =
        options.where((entry) => entry.$1 == value).firstOrNull?.$2 ??
        options.first.$2;
    final shape = StadiumBorder(side: BorderSide(color: c.border));
    return PopupMenuButton<T>(
      tooltip: label,
      initialValue: value,
      onSelected: onSelected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (_) => [
        for (final (id, text) in options)
          PopupMenuItem(value: id, child: Text(text)),
      ],
      child: Semantics(
        button: true,
        label: label,
        value: current,
        excludeSemantics: true,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: ShapeDecoration(color: c.surfaceAlt, shape: shape),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: c.accent),
              const SizedBox(width: 6),
              Text(
                current,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.expand_more_rounded, size: 19, color: c.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
