import 'package:flutter/material.dart';
import '../models/outline.dart';

class EstimatorBar extends StatelessWidget {
  final int totalPages;
  final int currentPage;
  final ChapterInfo? chapter;
  final double avgMinutesPerPage;
  final int statsTotalPages;

  const EstimatorBar({
    super.key,
    required this.totalPages,
    required this.currentPage,
    required this.chapter,
    required this.avgMinutesPerPage,
    required this.statsTotalPages,
  });

  @override
  Widget build(BuildContext context) {
    if (totalPages == 0) return const SizedBox.shrink();
    final remaining = (totalPages - currentPage).clamp(0, 9999);
    final bookEta = (remaining * avgMinutesPerPage).round();
    final ch = chapter;
    final chapterRemaining = ch == null ? null : (ch.end - currentPage).clamp(0, 9999);
    final chapterEta = chapterRemaining == null ? null : (chapterRemaining * avgMinutesPerPage).round();

    return Container(
      width: double.infinity,
      color: const Color(0xFF09090B),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Text('Faltam $remaining pág · ~${formatEta(bookEta)} para terminar',
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          if (ch != null && chapterRemaining != null && chapterRemaining > 0) ...[
            Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFF3F3F46), shape: BoxShape.circle)),
            Flexible(
              child: Text(
                'Cap. "${ch.title}" · faltam $chapterRemaining pág · ~${formatEta(chapterEta)}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else if (ch != null && chapterRemaining == 0) ...[
            Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFF3F3F46), shape: BoxShape.circle)),
            Text('Fim do capítulo "${ch.title}"', style: const TextStyle(color: Color(0xFF34D399), fontSize: 11)),
          ],
          if (statsTotalPages >= 10)
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.schedule, size: 11, color: Color(0xFF71717A)),
              const SizedBox(width: 4),
              Text('${avgMinutesPerPage.toStringAsFixed(1)} min/pág',
                  style: const TextStyle(color: Color(0xFF71717A), fontSize: 10)),
            ])
          else
            const Text('(estimativa padrão 2.0 min/pág)', style: TextStyle(color: Color(0xFF52525B), fontSize: 10)),
        ],
      ),
    );
  }
}
