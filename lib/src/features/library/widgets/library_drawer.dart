import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../api/api.dart';

class LibraryDrawer extends StatelessWidget {
  final VoidCallback onAddPdf;
  const LibraryDrawer({super.key, required this.onAddPdf});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF18181B),
      child: SafeArea(
        child: Column(children: [
          const SizedBox(height: 16),
          const Icon(Icons.menu_book, color: Colors.white, size: 32),
          const SizedBox(height: 8),
          const Text('PDF Translate', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          ListTile(
              leading: const Icon(Icons.bar_chart, color: Colors.white70),
              title: const Text('Estatísticas', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/stats');
              }),
          ListTile(
              leading: const Icon(Icons.add, color: Colors.white70),
              title: const Text('Adicionar PDF', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                onAddPdf();
              }),
          const Spacer(),
          const Divider(color: Colors.white12),
          ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text('Sair', style: TextStyle(color: Colors.white)),
              onTap: () async {
                await context.read<Api>().logout();
                if (context.mounted) Navigator.pushReplacementNamed(context, '/login');
              }),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }
}
