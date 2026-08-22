import 'package:pdfrx/pdfrx.dart';

class OutlineItem {
  final String title;
  final int page;
  final int depth;
  const OutlineItem(this.title, this.page, this.depth);
}

class ChapterInfo {
  final String title;
  final int start;
  final int end;
  const ChapterInfo({required this.title, required this.start, required this.end});
}

/// Extrai outline achatado com depth, igual ao web (pdfjs).
Future<List<OutlineItem>> loadOutlineFromBytes(List<int> bytes) async {
  final doc = await PdfDocument.openData(bytes as dynamic);
  try {
    final nodes = await doc.loadOutline();
    final flat = <OutlineItem>[];
    void walk(List<PdfOutlineNode> list, int depth) {
      for (final n in list) {
        final page = n.dest?.pageNumber ?? 0;
        if (page >= 1 && n.title.trim().isNotEmpty) {
          flat.add(OutlineItem(n.title.trim(), page, depth));
        }
        if (n.children.isNotEmpty) walk(n.children, depth + 1);
      }
    }
    walk(nodes, 0);
    return flat;
  } finally {
    await doc.dispose();
  }
}

/// Heurística de capítulos copiada do client/src/components/ReaderView.vue
List<OutlineItem> chaptersFromOutline(List<OutlineItem> outline) {
  if (outline.isEmpty) return [];
  final minD = outline.map((o) => o.depth).reduce((a, b) => a < b ? a : b);
  final minCount = outline.where((o) => o.depth == minD).length;
  if (minCount <= 3) {
    final next = outline.where((o) => o.depth == minD + 1).toList();
    if (next.length >= minCount * 3) return next;
  }
  return outline.where((o) => o.depth == minD).toList();
}

ChapterInfo? currentChapterOf({
  required List<OutlineItem> outline,
  required int currentPage,
  required int totalPages,
}) {
  final chs = chaptersFromOutline(outline);
  if (chs.isEmpty || totalPages == 0) return null;
  int idx = -1;
  for (int i = 0; i < chs.length; i++) {
    if (chs[i].page <= currentPage) idx = i;
  }
  if (idx == -1) return null;
  final cur = chs[idx];
  final next = idx + 1 < chs.length ? chs[idx + 1] : null;
  final end = next != null ? (next.page - 1).clamp(cur.page, totalPages).toInt() : totalPages;
  return ChapterInfo(title: cur.title, start: cur.page, end: end);
}

String formatEta(int? min) {
  if (min == null) return '—';
  if (min < 1) return '<1 min';
  if (min < 60) return '$min min';
  final h = min ~/ 60, m = min % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}min';
}
