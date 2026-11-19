import 'package:flutter/material.dart';

class ReadingPages<T> extends StatefulWidget {
  const ReadingPages({
    super.key,
    required this.rows,
    required this.builder,
    this.scrollToPageStart = false,
  });

  final List<T> rows;
  final Widget Function(BuildContext context, List<T> rows, Widget controls)
  builder;
  final bool scrollToPageStart;

  @override
  State<ReadingPages<T>> createState() => _ReadingPagesState<T>();
}

class _ReadingPagesState<T> extends State<ReadingPages<T>>
    with AutomaticKeepAliveClientMixin<ReadingPages<T>> {
  static const _pageSize = 10;
  final _startKey = GlobalKey();
  int _page = 0;
  @override
  bool get wantKeepAlive => true;

  int get _lastPage =>
      widget.rows.isEmpty ? 0 : (widget.rows.length - 1) ~/ _pageSize;

  @override
  void didUpdateWidget(ReadingPages<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _page = _page.clamp(0, _lastPage);
  }

  void _go(int page) {
    setState(() => _page = page);
    if (!widget.scrollToPageStart) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _startKey.currentContext;
      if (target != null) Scrollable.ensureVisible(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final start = _page * _pageSize;
    final rows = widget.rows
        .skip(start)
        .take(_pageSize)
        .toList(growable: false);
    final controls = _lastPage == 0
        ? const SizedBox.shrink()
        : Wrap(
            spacing: 4,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: _page > 0 ? () => _go(_page - 1) : null,
                child: const Text('Previous'),
              ),
              Semantics(
                liveRegion: true,
                child: Text(
                  '${start + 1}–${start + rows.length} of ${widget.rows.length}',
                ),
              ),
              TextButton(
                onPressed: _page < _lastPage ? () => _go(_page + 1) : null,
                child: const Text('Next'),
              ),
            ],
          );
    return KeyedSubtree(
      key: _startKey,
      child: widget.builder(context, rows, controls),
    );
  }
}
