import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../api/api.dart';

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
  int _initialPage = 1;
  Uint8List? _pdfBytes;
  bool _loading = true;
  String? _loadError;
  double _zoom = 1.0;
  static const _zoomSteps = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
  double _displayZoom() {
    if (_controller.isReady) {
      try { return _controller.value.getMaxScaleOnAxis(); } catch (_) {}
    }
    return _zoom;
  }

  Future<void> _zoomIn() async {
    if (!_controller.isReady) return;
    final cur = _displayZoom();
    double? next;
    for (final s in _zoomSteps) { if (s > cur + 0.01) { next = s; break; } }
    if (next == null) return;
    try {
      final center = _controller.visibleRect.center;
      await _controller.setZoom(center, next!);
      setState(() => _zoom = next!);
    } catch (_) {}
  }

  Future<void> _zoomOut() async {
    if (!_controller.isReady) return;
    final cur = _displayZoom();
    double? prev;
    for (int i = _zoomSteps.length - 1; i >= 0; i--) { if (_zoomSteps[i] < cur - 0.01) { prev = _zoomSteps[i]; break; } }
    if (prev == null) return;
    try {
      final center = _controller.visibleRect.center;
      await _controller.setZoom(center, prev!);
      setState(() => _zoom = prev!);
    } catch (_) {}
  }
  String? _selectedText;
  String? _translated;
  bool _translating = false;

  int _pendingPages = 0, _pendingMinutes = 0, _pendingHighlights = 0;
  int _lastStatPage = 1;
  String _tool = 'select';
  Color _color = const Color(0xFFFDE047);
  Timer? _saveTimer;
  Timer? _clock;

  String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _pageKey() => 'pdf-translate:page:${widget.book.key}';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onViewerChange);
    // leitura por minuto igual ao web
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent ?? true) {
        _queueStat(minutes: 1);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final api = context.read<Api>();
    int startPage = 1;
    try {
      final prefs = await SharedPreferences.getInstance();
      final local = prefs.getInt(_pageKey());
      if (local != null && local >= 1) startPage = local;
    } catch (_) {}
    try {
      final prog = await api.getProgress(widget.book.key);
      if (prog != null && prog.page >= 1) {
        startPage = prog.page;
        // sincroniza local com servidor
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(_pageKey(), startPage);
        } catch (_) {}
      }
    } catch (_) {
      // sem progresso no servidor — mantém local
    }
    try {
      final bytes = await api.getBookBytes(widget.book.key);
      if (!mounted) return;
      setState(() {
        _pdfBytes = bytes;
        _initialPage = startPage;
        _currentPage = startPage;
        _lastStatPage = startPage;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  void _onViewerChange() {
    if (!_controller.isReady) return;
    final p = _controller.pageNumber;
    final total = _controller.pageCount;
    if (total != 0 && total != _totalPages) {
      setState(() => _totalPages = total);
    }
    // sincroniza zoom exibido com o real do controller (pinch + botoes)
    try {
      final z = _controller.value.getMaxScaleOnAxis();
      if ((z - _zoom).abs() > 0.01) setState(() => _zoom = z);
    } catch (_) {}
    if (p != null && p != _currentPage) {
      setState(() => _currentPage = p);
      if (p > _lastStatPage) _queueStat(pages: (p - _lastStatPage).clamp(0, 100));
      _lastStatPage = p;
      _saveProgress(p);
      SharedPreferences.getInstance().then((pr) => pr.setInt(_pageKey(), p));
    }
  }

  void _saveProgress(int page) {
    if (_totalPages < 1) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      context.read<Api>().saveProgress(widget.book.key, page, _totalPages).catchError((_) {});
    });
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
      try {
        await context.read<Api>().addStats(date: date, pages: p, minutes: m, highlights: h);
      } catch (_) {}
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
  void dispose() {
    _controller.removeListener(_onViewerChange);
    _saveTimer?.cancel();
    _clock?.cancel();
    // garante último save
    if (_totalPages >= 1) {
      try {
        SharedPreferences.getInstance().then((pr) => pr.setInt(_pageKey(), _currentPage));
      } catch (_) {}
    }
    super.dispose();
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
          IconButton(onPressed: _zoomOut, icon: const Icon(Icons.remove, color: Colors.white70)),
          Center(child: Text('${(_displayZoom() * 100).round()}%', style: const TextStyle(color: Colors.white70, fontSize: 12))),
          IconButton(onPressed: _zoomIn, icon: const Icon(Icons.add, color: Colors.white70)),
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
            Text('$_currentPage / ${_totalPages == 0 ? "—" : _totalPages}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
                  ? Center(child: Text(_loadError!, style: const TextStyle(color: Colors.redAccent)))
                  : _pdfBytes == null
                      ? const Center(child: Text('Sem dados', style: TextStyle(color: Colors.white54)))
                      : PdfViewer.data(
                          _pdfBytes!,
                          sourceName: widget.book.name,
                          controller: _controller,
                          initialPageNumber: _initialPage,
                          params: const PdfViewerParams(),
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
