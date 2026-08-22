import 'package:flutter/material.dart';
import '../models/outline.dart';

class OutlineSidebar extends StatelessWidget {
  final List<OutlineItem> outline;
  final int currentPage;
  final ValueChanged<int> onJump;
  final VoidCallback onClose;

  const OutlineSidebar({
    super.key,
    required this.outline,
    required this.currentPage,
    required this.onJump,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      decoration: const BoxDecoration(
        color: Color(0xFF09090B),
        border: Border(right: BorderSide(color: Color(0xFF27272A))),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF27272A)))),
          child: Row(children: [
            const Text('Índice', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            InkWell(onTap: onClose, child: const Icon(Icons.close, size: 18, color: Colors.white54)),
          ]),
        ),
        Expanded(
          child: outline.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Este livro não tem índice.', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ),
                )
              : ListView.builder(
                  itemCount: outline.length,
                  itemBuilder: (_, i) {
                    final item = outline[i];
                    final isCurrent = item.page == currentPage;
                    return InkWell(
                      onTap: () => onJump(item.page),
                      child: Container(
                        padding: EdgeInsets.only(left: 12 + item.depth * 16, right: 12, top: 8, bottom: 8),
                        color: isCurrent ? const Color(0xFF27272A) : null,
                        child: Row(children: [
                          Expanded(
                            child: Text(item.title,
                                style: TextStyle(color: isCurrent ? Colors.white : Colors.white70, fontSize: 12),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 8),
                          Text('${item.page}', style: TextStyle(color: isCurrent ? Colors.white70 : Colors.white38, fontSize: 11)),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
