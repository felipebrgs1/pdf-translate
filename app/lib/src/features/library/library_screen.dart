import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api.dart';

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
                          onTap: () => Navigator.pushNamed(context, '/reader', arguments: b),
                          child: Container(
                            decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Icon(Icons.picture_as_pdf, color: Colors.white30, size: 40),
                              const SizedBox(height: 8),
                              Text(b.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13)),
                              const Spacer(),
                              if (b.progress != null) LinearProgressIndicator(value: (b.progress!.percent / 100).clamp(0, 1)),
                              const SizedBox(height: 4),
                              Text('${(b.size / 1024).toStringAsFixed(0)} KB', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                            ]),
                          ),
                        );
                      },
                    ),
    );
  }
}
