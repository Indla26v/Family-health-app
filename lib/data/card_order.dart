/// Sorts Health cards by the user's chosen order (`cond:<id>` / `test:<key>`
/// keys): cards in [order] come first in that order, the rest follow by name (A–Z).
List<T> byUserOrder<T>(Iterable<T> items, String Function(T) keyOf, String Function(T) nameOf, List<String> order) {
  final pos = {for (var i = 0; i < order.length; i++) order[i]: i};
  return items.toList()
    ..sort((a, b) {
      final pa = pos[keyOf(a)], pb = pos[keyOf(b)];
      if (pa != null || pb != null) return (pa ?? 1 << 30).compareTo(pb ?? 1 << 30);
      return nameOf(a).toLowerCase().compareTo(nameOf(b).toLowerCase());
    });
}
