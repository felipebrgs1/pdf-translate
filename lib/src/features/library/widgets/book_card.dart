import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../api/api.dart';
import '../../../cache/pdf_cache.dart';

class BookCard extends StatelessWidget {
  final Book book;
  final VoidCallback onOpen;
  final VoidCallback onCompress;
  final VoidCallback onRemove;
  final Future<Uint8List?> Function(String key) ensureThumb;

  const BookCard({
    super.key,
    required this.book,
    required this.onOpen,
    required this.onCompress,
    required this.onRemove,
    required this.ensureThumb,
  });

  @override
  Widget build(BuildContext context) {
    final b = book;
    return GestureDetector(
      onSecondaryTapDown: (d) async {
        final v = await showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(d.globalPosition.dx, d.globalPosition.dy, d.globalPosition.dx, d.globalPosition.dy),
          items: const [
            PopupMenuItem(value: 'compress', child: Row(children: [Icon(Icons.compress, size: 18), SizedBox(width: 8), Text('Comprimir')])),
            PopupMenuItem(value: 'remove', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.redAccent), SizedBox(width: 8), Text('Remover')])),
          ],
        );
        if (v == 'compress') onCompress();
        if (v == 'remove') onRemove();
      },
      child: InkWell(
        onTap: onOpen,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Stack(children: [
                Positioned.fill(
                  child: FutureBuilder<Uint8List?>(
                    future: context.read<Api>().getThumbBytes(b.key),
                    builder: (_, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return Container(
                            color: const Color(0xFF18181B),
                            child: const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))));
                      }
                      final bytes = snap.data;
                      if (bytes != null && bytes.isNotEmpty) {
                        return Image.memory(bytes,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) =>
                                Container(color: const Color(0xFF18181B), child: const Icon(Icons.broken_image, color: Colors.white24)));
                      }
                      return FutureBuilder<Uint8List?>(
                        future: ensureThumb(b.key),
                        builder: (_, snap2) {
                          if (snap2.connectionState == ConnectionState.waiting) {
                            return Container(
                                color: const Color(0xFF18181B),
                                child: const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))));
                          }
                          final tb = snap2.data;
                          if (tb != null && tb.isNotEmpty) return Image.memory(tb, fit: BoxFit.cover, gaplessPlayback: true);
                          return Container(
                              color: const Color(0xFF18181B),
                              child: const Center(child: Icon(Icons.picture_as_pdf, color: Colors.white24, size: 40)));
                        },
                      );
                    },
                  ),
                ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: FutureBuilder<bool>(
                    future: isPdfCached(b.key),
                    builder: (_, snap) {
                      final cached = snap.data == true;
                      if (!cached) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
                        child: const Icon(Icons.offline_pin, size: 14, color: Color(0xFF4ADE80)),
                      );
                    },
                  ),
                ),
                Positioned(
                  left: 6,
                  top: 6,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
                        child: const Icon(Icons.more_vert, size: 14, color: Colors.white70)),
                    onSelected: (v) {
                      if (v == 'compress') onCompress();
                      if (v == 'remove') onRemove();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'compress', child: Row(children: [Icon(Icons.compress, size: 18), SizedBox(width: 8), Text('Comprimir')])),
                      PopupMenuItem(value: 'remove', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.redAccent), SizedBox(width: 8), Text('Remover')])),
                    ],
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13)),
                const SizedBox(height: 6),
                if (b.progress != null) ...[
                  Text(
                      'Página ${b.progress!.page} de ${b.progress!.totalPages} · ${b.progress!.percent % 1 == 0 ? b.progress!.percent.toStringAsFixed(0) : b.progress!.percent.toStringAsFixed(1)}%',
                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: (b.progress!.percent / 100).clamp(0, 1), minHeight: 3),
                  const SizedBox(height: 4),
                  Text('${(b.size / 1024).toStringAsFixed(0)} KB', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ] else
                  Text('${(b.size / 1024).toStringAsFixed(0)} KB', style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
