import 'package:flutter/material.dart';

class TranslationSheet extends StatelessWidget {
  final String? selectedText;
  final String? translated;
  final bool translating;
  final VoidCallback onClose;

  const TranslationSheet({
    super.key,
    required this.selectedText,
    required this.translated,
    required this.translating,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedText == null) return const SizedBox.shrink();
    return Container(
      color: const Color(0xFF18181B),
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Expanded(
          child: Text(translated ?? (translating ? 'Traduzindo…' : selectedText!),
              style: const TextStyle(color: Colors.white)),
        ),
        IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: onClose),
      ]),
    );
  }
}
