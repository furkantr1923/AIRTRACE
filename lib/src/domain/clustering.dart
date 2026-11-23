import 'dart:ui';

/// Ekran koordinatlarında ızgara tabanlı kümelendirme. O(n), bellek dostu.
///
/// Bir hücrede [minClusterSize] veya daha fazla uçak varsa tek bir küme
/// balonu çizilir; daha azsa uçaklar tek tek çizilir.
class GridClusterer {
  GridClusterer({this.cellSize = 46, this.minClusterSize = 4});

  final double cellSize;
  final int minClusterSize;

  final Map<int, _Cell> _cells = {};

  ClusterResult run(List<Offset> points) {
    _cells.clear();
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final key = ((p.dx / cellSize).floor() & 0xFFFF) << 16 | ((p.dy / cellSize).floor() & 0xFFFF);
      (_cells[key] ??= _Cell()).add(i, p);
    }
    final singles = <int>[];
    final clusters = <Cluster>[];
    for (final c in _cells.values) {
      if (c.indices.length >= minClusterSize) {
        clusters.add(Cluster(Offset(c.sx / c.indices.length, c.sy / c.indices.length), c.indices.length));
      } else {
        singles.addAll(c.indices);
      }
    }
    return ClusterResult(singles, clusters);
  }
}

class _Cell {
  final List<int> indices = [];
  double sx = 0, sy = 0;
  void add(int i, Offset p) {
    indices.add(i);
    sx += p.dx;
    sy += p.dy;
  }
}

class Cluster {
  const Cluster(this.center, this.count);
  final Offset center;
  final int count;
}

class ClusterResult {
  const ClusterResult(this.singles, this.clusters);

  /// Tek tek çizilecek noktaların dizinleri.
  final List<int> singles;
  final List<Cluster> clusters;
}
