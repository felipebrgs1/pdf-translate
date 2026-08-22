import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import '../../api/api.dart';

// Leitor com pdfrx — replica PdfViewer.vue + TranslatePopup + anotações.
// Por enquanto usa overlay de ferramentas e viewer básico; iterar para seleção/tradução completa.
class ReaderScreen extends StatefulWidget {
  final Book book;
  const ReaderScreen({super.key, required this.book});
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _controller = PdfViewerController();
  int _currentPage = 1;
  int _totalPages = 0;
  double _zoom = 1.0;
  String? _selectedText;
  String? _translated;
  bool _translating = false;

  int _pendingPages = 0, _pendingMinutes = 0, _pendingHighlights = 0;
  int _lastStatPage = 1;
  String _tool = 'select';
  Color _color = const Color(0xFFFDE047);

  String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  void _queueStat({int pages = 0, int minutes = 0, int highlights = 0}) {
    _pendingPages += pages;
    _pendingMinutes += minutes;
    _pendingHighlights += highlights;
    Future.delayed(const Duration(seconds: 5), () async {
      if (!mounted) return;
      if (_pendingPages == 0 && _pendingMinutes == 0 && _pendingHighlights == 0) return;
      final date = _today();
      final p = _pendingPages, m = _pendingMinutes, h = _pendingHighlights;
      _pendingPages = 0; _pendingMinutes = 0; _pendingHighlights = 0;
      try { await context.read<Api>().addStats(date: date, pages: p, minutes: m, highlights: h); } catch (_) {}
    });
  }

  String _formatEta(int? min) {
    if (min == null) return '—';
    if (min < 1) return '<1 min';
    if (min < 60) return '$min min';
    final h = min ~/ 60, m = min % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}min';
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<Api>();
    final remaining = (_totalPages - _currentPage).clamp(0, 9999);
    final eta = remaining * 2;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white70), onPressed: () => Navigator.pop(context)),
        title: Text(widget.book.name, style: const TextStyle(color: Colors.white, fontSize: 14), overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(onPressed: () => setState(() => _zoom = (_zoom - 0.25).clamp(0.5, 3.0)), icon: const Icon(Icons.remove, color: Colors.white70)),
          Center(child: Text('${(_zoom * 100).round()}%', style: const TextStyle(color: Colors.white70, fontSize: 12))),
          IconButton(onPressed: () => setState(() => _zoom = (_zoom + 0.25).clamp(0.5, 3.0)), icon: const Icon(Icons.add, color: Colors.white70)),
        ],
      ),
      body: Column(children: [
        Container(
          color: const Color(0xFF09090B),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            _toolBtn(Icons.touch_app, 'select'),
            _toolBtn(Icons.highlight, 'highlight'),
            _toolBtn(Icons.edit, 'draw'),
            _toolBtn(Icons.cleaning_services, 'erase'),
            if (_tool == 'highlight' || _tool == 'draw') ...[
              const SizedBox(width: 8),
              for (final c in [0xFFFDE047, 0xFF86EFAC, 0xFFFCA5A5, 0xFF93C5FD])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    onTap: () => setState(() => _color = Color(c)),
                    child: CircleAvatar(
                      backgroundColor: Color(c),
                      radius: 9,
                      child: _color.toARGB32() == c ? const Icon(Icons.check, size: 12, color: Colors.black) : null,
                    ),
                  ),
                ),
            ],
            const Spacer(),
            Text('$_currentPage / $_totalPages', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
        if (_totalPages > 0)
          Container(
            width: double.infinity,
            color: const Color(0xFF09090B),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text('Faltam $remaining pág · ~${_formatEta(eta)} para terminar', style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ),
        Expanded(
          child: FutureBuilder<Uint8List>(
            future: api.getBookBytes(widget.book.key),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (snap.hasError || !snap.hasData) return Center(child: Text('Erro: ${snap.error}', style: const TextStyle(color: Colors.redAccent)));
              return PdfViewer.data(
                snap.data!,
                sourceName: widget.book.name,
                controller: _controller,
                params: const PdfViewerParams(),
              );
            },
          ),
        ),
        if (_selectedText != null)
          Container(
            color: const Color(0xFF18181B),
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: Text(_translated ?? (_translating ? 'Traduzindo…' : _selectedText!), style: const TextStyle(color: Colors.white))),
              IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => setState(() { _selectedText = null; _translated = null; })),
            ]),
          ),
      ]),
      floatingActionButton: _selectedText == null
          ? null
          : FloatingActionButton.small(
              onPressed: () async {
                if (_selectedText == null) return;
                setState(() => _translating = true);
                try {
                  final t = await api.translate(_selectedText!, 'pt');
                  if (mounted) setState(() => _translated = t);
                } finally {
                  if (mounted) setState(() => _translating = false);
                }
              },
              child: const Icon(Icons.translate),
            ),
    );
  }

  Widget _toolBtn(IconData icon, String id) {
    final active = _tool == id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: () => setState(() => _tool = id),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: active ? Colors.white12 : null, borderRadius: BorderRadius.circular(6)),
          child: Icon(icon, size: 18, color: active ? Colors.white : Colors.white54),
        ),
      ),
    );
  }
}
