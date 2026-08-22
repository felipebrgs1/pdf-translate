import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api.dart';
import '../../cache/pdf_cache.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Book> _books = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = context.read<Api>();
      _books = await api.listBooks();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAndUpload() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    if (res == null || res.files.single.bytes == null) return;
    final f = res.files.single;
    try {
      final api = context.read<Api>();
      await api.uploadBook(f.bytes!, f.name);
      await _refresh();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Biblioteca', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(onPressed: () => Navigator.pushNamed(context, '/stats'), icon: const Icon(Icons.bar_chart, color: Colors.white70)),
          IconButton(onPressed: _pickAndUpload, icon: const Icon(Icons.add, color: Colors.white)),
          IconButton(
              onPressed: () async { await context.read<Api>().logout(); if (mounted) Navigator.pushReplacementNamed(context, '/login'); },
              icon: const Icon(Icons.logout, color: Colors.white70)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : _books.isEmpty
                  ? const Center(child: Text('Nenhum livro ainda', style: TextStyle(color: Colors.white54)))
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.65, crossAxisSpacing: 12, mainAxisSpacing: 12),
                      itemCount: _books.length,
                      itemBuilder: (_, i) {
                        final b = _books[i];
                        return InkWell(
                          onTap: () => Navigator.pushNamed(context, '/reader', arguments: b).then((_) => _refresh()),
                          child: Container(
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(12)),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              // capa autenticada + selo offline
                              Expanded(
                                child: Stack(children: [
                                  Positioned.fill(
                                    child: FutureBuilder<Uint8List?>(
                                      future: context.read<Api>().getThumbBytes(b.key),
                                      builder: (_, snap) {
                                        if (snap.connectionState == ConnectionState.waiting) {
                                          return Container(color: const Color(0xFF18181B), child: const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))));
                                        }
                                        final bytes = snap.data;
                                        if (bytes != null && bytes.isNotEmpty) {
                                          return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true,
                                              errorBuilder: (_, __, ___) => Container(color: const Color(0xFF18181B), child: const Icon(Icons.broken_image, color: Colors.white24)));
                                        }
                                        return Container(
                                          color: const Color(0xFF18181B),
                                          child: const Center(child: Icon(Icons.picture_as_pdf, color: Colors.white24, size: 40)),
                                        );
                                      },
                                    ),
                                  ),
                                  // icone offline (aparece apos abrir o livro uma vez)
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
                                ]),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(b.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13)),
                                  const SizedBox(height: 6),
                                  if (b.progress != null) ...[
                                    Text('Página ${b.progress!.page} de ${b.progress!.totalPages} · ${b.progress!.percent % 1 == 0 ? b.progress!.percent.toStringAsFixed(0) : b.progress!.percent.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white70, fontSize: 11)),
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
                        );
                      },
                    ),
    );
  }
}
