import 'package:flutter/material.dart';

class ReaderToolbar extends StatelessWidget {
  final bool hasOutline;
  final bool showOutline;
  final VoidCallback onToggleOutline;
  final String tool;
  final ValueChanged<String> onToolChanged;
  final Color color;
  final ValueChanged<Color> onColorChanged;
  final int currentPage;
  final int totalPages;

  const ReaderToolbar({
    super.key,
    required this.hasOutline,
    required this.showOutline,
    required this.onToggleOutline,
    required this.tool,
    required this.onToolChanged,
    required this.color,
    required this.onColorChanged,
    required this.currentPage,
    required this.totalPages,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF09090B),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(children: [
        if (hasOutline)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: InkWell(
              onTap: onToggleOutline,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: showOutline ? Colors.white12 : null,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: showOutline ? Colors.white24 : const Color(0xFF27272A)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.list, size: 16, color: showOutline ? Colors.white : Colors.white70),
                  const SizedBox(width: 4),
                  Text('Índice', style: TextStyle(color: showOutline ? Colors.white : Colors.white70, fontSize: 12)),
                ]),
              ),
            ),
          ),
        _toolBtn(Icons.touch_app, 'select'),
        _toolBtn(Icons.highlight, 'highlight'),
        _toolBtn(Icons.edit, 'draw'),
        _toolBtn(Icons.cleaning_services, 'erase'),
        if (tool == 'highlight' || tool == 'draw') ...[
          const SizedBox(width: 8),
          for (final c in [0xFFFDE047, 0xFF86EFAC, 0xFFFCA5A5, 0xFF93C5FD])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: InkWell(
                onTap: () => onColorChanged(Color(c)),
                child: CircleAvatar(
                  backgroundColor: Color(c),
                  radius: 9,
                  child: color.toARGB32() == c ? const Icon(Icons.check, size: 12, color: Colors.black) : null,
                ),
              ),
            ),
        ],
        const Spacer(),
        Text('$currentPage / ${totalPages == 0 ? "—" : totalPages}',
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
    );
  }

  Widget _toolBtn(IconData icon, String id) {
    final active = tool == id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: () => onToolChanged(id),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: active ? Colors.white12 : null, borderRadius: BorderRadius.circular(6)),
          child: Icon(icon, size: 18, color: active ? Colors.white : Colors.white54),
        ),
      ),
    );
  }
}
