import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  Map<String, DayStats> _days = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = context.read<Api>();
      final days = await api.getStats();
      if (mounted) setState(() { _days = days; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final year = now.year;
    final yearKey = year.toString();
    int pagesYear = 0, minsYear = 0, highYear = 0, totalPages = 0, totalMins = 0;
    _days.forEach((k, v) {
      totalPages += v.pages; totalMins += v.minutes;
      if (k.startsWith(yearKey)) { pagesYear += v.pages; minsYear += v.minutes; highYear += v.highlights; }
    });

    // streak
    int streak = 0;
    var d = DateTime.now();
    if ((_days['${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}']?.pages ?? 0) == 0) {
      d = d.subtract(const Duration(days: 1));
    }
    while (true) {
      final k = '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
      if ((_days[k]?.pages ?? 0) > 0) { streak++; d = d.subtract(const Duration(days: 1)); } else break;
      if (streak > 3650) break;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: const Text('Estatísticas', style: TextStyle(color: Colors.white))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Row(children: [
                  _card('Páginas em $year', '$pagesYear', 'dias ativos'),
                  const SizedBox(width: 12),
                  _card('Tempo em $year', '${minsYear}min', '$highYear marcações'),
                  const SizedBox(width: 12),
                  _card('Sequência', '$streak dias', 'seguidos'),
                  const SizedBox(width: 12),
                  _card('Total', '$totalPages', '${totalMins}min'),
                ]),
                const SizedBox(height: 16),
                Expanded(
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 53),
                    itemCount: 53 * 7,
                    itemBuilder: (_, i) {
                      // heatmap simplificado: 371 dias terminando hoje, intensidade por páginas
                      final date = DateTime.now().subtract(Duration(days: 53 * 7 - 1 - i));
                      final k = '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
                      final p = _days[k]?.pages ?? 0;
                      Color c = const Color(0xFF27272A);
                      if (p > 0 && p <= 2) c = const Color(0xFF022C22);
                      else if (p <= 6) c = const Color(0xFF065F46);
                      else if (p <= 12) c = const Color(0xFF059669);
                      else if (p > 12) c = const Color(0xFF34D399);
                      return Container(margin: const EdgeInsets.all(1), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)));
                    },
                  ),
                ),
              ]),
            ),
    );
  }

  Widget _card(String title, String value, String sub) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(12), color: const Color(0xFF18181B)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white54, fontSize: 10)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            Text(sub, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ]),
        ),
      );
}
