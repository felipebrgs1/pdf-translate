import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../api/api.dart';
import '../../cache/pdf_cache.dart';
import 'models/outline.dart';
import 'widgets/estimator_bar.dart';
import 'widgets/outline_sidebar.dart';
import 'widgets/reader_toolbar.dart';
import 'widgets/translation_sheet.dart';

class ReaderScreen extends StatefulWidget {
  final Book book;
  const ReaderScreen({super.key, required this.book});
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _controller = PdfViewerController();
  final _focusNode = FocusNode();

  int _currentPage = 1, _totalPages = 0, _initialPage = 1;
  Uint8List? _pdfBytes;
  bool _loading = true;
  String? _loadError;
  double _zoom = 1.0;

  // índice / capítulo
  List<OutlineItem> _outline = [];
  bool _showOutline = false;
  Map<String, DayStats> _statsDays = {};
  ChapterInfo? get _chapter => currentChapterOf(outline: _outline, currentPage: _currentPage, totalPages: _totalPages);
  int get _statsTotalPages => _statsDays.values.fold(0, (s, d) => s + d.pages) + _pendingPages;
  double get _avgMinutesPerPage {
    final p = _statsTotalPages;
    final m = _statsDays.values.fold(0, (s, d) => s + d.minutes) + _pendingMinutes;
    if (p >= 10 && m >= 5) return m / p;
    return 2;
  }

  // seleção / tradução
  String? _selectedText, _translated;
  bool _translating = false;
  Timer? _selectionDebounce;

  // anotação / stats
  String _tool = 'select';
  Color _color = const Color(0xFFFDE047);
  int _pendingPages = 0, _pendingMinutes = 0, _pendingHighlights = 0;
  int _lastStatPage = 1;
  Timer? _saveTimer, _clock;

  static const _zoomSteps = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];

  String _pageKey() => 'pdf-translate:page:${widget.book.key}';
  String _today() => DateTime.now().toIso8601String().substring(0, 10);

  // ── zoom ──
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
      // ignore: unnecessary_non_null_assertion
      await _controller.setZoom(_controller.visibleRect.center, next!);
      // ignore: unnecessary_non_null_assertion
      setState(() => _zoom = next!);
      _focusNode.requestFocus();
    } catch (_) {}
  }

  Future<void> _zoomOut() async {
    if (!_controller.isReady) return;
    final cur = _displayZoom();
    double? prev;
    for (int i = _zoomSteps.length - 1; i >= 0; i--) { if (_zoomSteps[i] < cur - 0.01) { prev = _zoomSteps[i]; break; } }
    if (prev == null) return;
    try {
      // ignore: unnecessary_non_null_assertion
      await _controller.setZoom(_controller.visibleRect.center, prev!);
      // ignore: unnecessary_non_null_assertion
      setState(() => _zoom = prev!);
      _focusNode.requestFocus();
    } catch (_) {}
  }

  void _onSelectionChanged(PdfTextSelection sel) {
    if (!sel.hasSelectedText) {
      _selectionDebounce?.cancel();
      if (mounted) setState(() { _selectedText = null; _translated = null; _translating = false; });
      return;
    }
    _selectionDebounce?.cancel();
    _selectionDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final text = (await sel.getSelectedText()).trim();
        if (text.isEmpty || text.length < 2 || !mounted) return;
        setState(() { _selectedText = text; _translated = null; _translating = true; });
        final t = await context.read<Api>().translate(text, 'pt');
        if (!mounted) return;
        setState(() { _translated = t; _translating = false; });
      } catch (_) {
        if (mounted) setState(() => _translating = false);
      }
    });
  }

  // ── navegação / stats ──
  bool _handleHardwareKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) { _nextPage(); return true; }
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) { _prevPage(); return true; }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) { _scrollBy(-300); return true; }
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) { _scrollBy(300); return true; }
    return false;
  }

  Future<void> _scrollBy(double dy) async {
    if (!_controller.isReady) return;
    try {
      final cur = _controller.visibleRect;
      final maxY = (_controller.documentSize.height - _controller.viewSize.height / _controller.value.getMaxScaleOnAxis()).clamp(0, double.infinity);
      final ny = (cur.top + dy).clamp(0.0, maxY is double ? maxY : double.infinity);
      await _controller.goToPosition(documentOffset: Offset(cur.left, ny.toDouble()));
    } catch (_) {}
  }

  Future<void> _nextPage() async { if (_controller.isReady && _currentPage < _totalPages) { try { await _controller.goToPage(pageNumber: _currentPage + 1); } catch (_) {} } }
  Future<void> _prevPage() async { if (_controller.isReady && _currentPage > 1) { try { await _controller.goToPage(pageNumber: _currentPage - 1); } catch (_) {} } }
  void _jumpToPage(int p) async { if (!_controller.isReady) return; try { await _controller.goToPage(pageNumber: p.clamp(1, _totalPages == 0 ? 9999 : _totalPages)); } catch (_) {} _focusNode.requestFocus(); }

  void _queueStat({int pages = 0, int minutes = 0, int highlights = 0}) {
    _pendingPages += pages; _pendingMinutes += minutes; _pendingHighlights += highlights;
    Future.delayed(const Duration(seconds: 5), () async {
      if (!mounted || (_pendingPages == 0 && _pendingMinutes == 0 && _pendingHighlights == 0)) return;
      final date = _today(); final p = _pendingPages, m = _pendingMinutes, h = _pendingHighlights;
      _pendingPages = 0; _pendingMinutes = 0; _pendingHighlights = 0;
      try { await context.read<Api>().addStats(date: date, pages: p, minutes: m, highlights: h); } catch (_) {}
    });
  }

  void _saveProgress(int page) {
    if (_totalPages < 1) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      context.read<Api>().saveProgress(widget.book.key, page, _totalPages).catchError((_) => BookProgress(page: page, totalPages: _totalPages, percent: 0, updatedAt: ''));
    });
  }

  // ── lifecycle ──
  @override
  void initState() {
    super.initState();
    _controller.addListener(_onViewerChange);
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) { if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) _queueStat(minutes: 1); });
    WidgetsBinding.instance.addPostFrameCallback((_) { _load(); _focusNode.requestFocus(); });
  }

  Future<void> _load() async {
    final api = context.read<Api>();
    int startPage = 1;
    try { final prefs = await SharedPreferences.getInstance(); final local = prefs.getInt(_pageKey()); if (local != null && local >= 1) startPage = local; } catch (_) {}
    try { final prog = await api.getProgress(widget.book.key); if (prog != null && prog.page >= 1) { startPage = prog.page; try { final prefs = await SharedPreferences.getInstance(); await prefs.setInt(_pageKey(), startPage); } catch (_) {} } } catch (_) {}

    Uint8List? bytes; String? bytesError;
    try { final fetched = await api.getBookBytes(widget.book.key); bytes = fetched; await savePdfToCache(widget.book.key, fetched); }
    catch (e) { bytesError = e.toString(); try { final f = await cachedPdfFile(widget.book.key); if (await f.exists()) bytes = await f.readAsBytes(); } catch (_) {} }

    if (!mounted) return;
    if (bytes != null && bytes.isNotEmpty) {
      setState(() { _pdfBytes = bytes; _initialPage = startPage; _currentPage = startPage; _lastStatPage = startPage; _loading = false; });
      _loadOutline(bytes); _loadStats();
    } else {
      setState(() { _loadError = bytesError ?? 'Falha ao carregar PDF e sem cache offline'; _loading = false; });
    }
  }

  Future<void> _loadOutline(Uint8List bytes) async {
    try { final flat = await loadOutlineFromBytes(bytes); if (mounted) setState(() => _outline = flat); } catch (_) {}
  }

  Future<void> _loadStats() async {
    try { final d = await context.read<Api>().getStats(); if (mounted) setState(() => _statsDays = d); } catch (_) {}
  }

  void _onViewerChange() {
    if (!_controller.isReady) return;
    final p = _controller.pageNumber; final total = _controller.pageCount;
    if (total != 0 && total != _totalPages) setState(() => _totalPages = total);
    try { final z = _controller.value.getMaxScaleOnAxis(); if ((z - _zoom).abs() > 0.01) setState(() => _zoom = z); } catch (_) {}
    if (p != null && p != _currentPage) {
      setState(() => _currentPage = p);
      if (p > _lastStatPage) _queueStat(pages: (p - _lastStatPage).clamp(0, 100));
      _lastStatPage = p; _saveProgress(p);
      SharedPreferences.getInstance().then((pr) => pr.setInt(_pageKey(), p));
    }
  }

  @override
  void dispose() {
    _selectionDebounce?.cancel(); HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _focusNode.dispose(); _controller.removeListener(_onViewerChange);
    _saveTimer?.cancel(); _clock?.cancel();
    if (_totalPages >= 1) { try { SharedPreferences.getInstance().then((pr) => pr.setInt(_pageKey(), _currentPage)); } catch (_) {} }
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) => KeyEventResult.ignored;

  // ── build ──
  @override
  Widget build(BuildContext context) {
    final api = context.read<Api>();
    return Focus(
      focusNode: _focusNode, autofocus: true, onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white70), onPressed: () => Navigator.pop(context)),
          title: Text(widget.book.name, style: const TextStyle(color: Colors.white, fontSize: 14), overflow: TextOverflow.ellipsis),
          actions: [
            if (_outline.isNotEmpty) IconButton(tooltip: 'Índice', icon: Icon(_showOutline ? Icons.menu_book : Icons.menu_book_outlined, color: _showOutline ? Colors.white : Colors.white70), onPressed: () => setState(() => _showOutline = !_showOutline)),
            IconButton(onPressed: _zoomOut, icon: const Icon(Icons.remove, color: Colors.white70)),
            Center(child: Text('${(_displayZoom() * 100).round()}%', style: const TextStyle(color: Colors.white70, fontSize: 12))),
            IconButton(onPressed: _zoomIn, icon: const Icon(Icons.add, color: Colors.white70)),
          ],
        ),
        body: Column(children: [
          ReaderToolbar(hasOutline: _outline.isNotEmpty, showOutline: _showOutline, onToggleOutline: () => setState(() => _showOutline = !_showOutline), tool: _tool, onToolChanged: (v) => setState(() => _tool = v), color: _color, onColorChanged: (c) => setState(() => _color = c), currentPage: _currentPage, totalPages: _totalPages),
          EstimatorBar(totalPages: _totalPages, currentPage: _currentPage, chapter: _chapter, avgMinutesPerPage: _avgMinutesPerPage, statsTotalPages: _statsTotalPages),
          Expanded(
            child: Row(children: [
              if (_showOutline) OutlineSidebar(outline: _outline, currentPage: _currentPage, onJump: _jumpToPage, onClose: () => setState(() => _showOutline = false)),
              Expanded(
                child: TextSelectionTheme(
                  data: const TextSelectionThemeData(selectionColor: Color(0x663B82F6), selectionHandleColor: Color(0xFF3B82F6), cursorColor: Color(0xFF3B82F6)),
                  child: _loading ? const Center(child: CircularProgressIndicator())
                      : _loadError != null ? Center(child: Text(_loadError!, style: const TextStyle(color: Colors.redAccent)))
                      : _pdfBytes == null ? const Center(child: Text('Sem dados', style: TextStyle(color: Colors.white54)))
                      : PdfViewer.data(_pdfBytes!, sourceName: widget.book.name, controller: _controller, initialPageNumber: _initialPage,
                          params: PdfViewerParams(textSelectionParams: PdfTextSelectionParams(enabled: true, showContextMenuAutomatically: false, onTextSelectionChange: _onSelectionChanged))),
                ),
              ),
            ]),
          ),
          TranslationSheet(selectedText: _selectedText, translated: _translated, translating: _translating, onClose: () => setState(() { _selectedText = null; _translated = null; })),
        ]),
        floatingActionButton: _selectedText == null ? null : FloatingActionButton.small(
          onPressed: () async { if (_selectedText == null) return; setState(() => _translating = true); try { final t = await api.translate(_selectedText!, 'pt'); if (mounted) setState(() => _translated = t); } finally { if (mounted) setState(() => _translating = false); } },
          child: const Icon(Icons.translate),
        ),
      ),
    );
  }
}
