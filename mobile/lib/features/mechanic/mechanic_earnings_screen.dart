import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/history_job_card.dart';
import '../../models/history_models.dart';
import '../../models/bid_model.dart';
import '../../providers/history_controller.dart';
import '../../services/history_service.dart';

class MechanicEarningsScreen extends StatefulWidget {
  const MechanicEarningsScreen({super.key, this.service});
  final HistoryService? service;
  @override
  State<MechanicEarningsScreen> createState() => _MechanicEarningsScreenState();
}

class _MechanicEarningsScreenState extends State<MechanicEarningsScreen>
    with WidgetsBindingObserver {
  late final HistoryController _history;
  String _period = 'All Time';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _history = HistoryController(
        service: widget.service, mechanic: true, earnings: true)
      ..addListener(_changed);
    _history.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _reload() {
    final now = DateTime.now().toUtc();
    final start = _period == 'This Month'
        ? DateTime.utc(now.year, now.month)
        : _period == 'This Year'
            ? DateTime.utc(now.year)
            : null;
    return _history.filter(
        from: start?.toIso8601String().substring(0, 10),
        to: start == null ? null : now.toIso8601String().substring(0, 10));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _history.removeListener(_changed);
    _history.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _history.summary;
    final missing = summary?['unpricedJobs'] as int? ?? 0;
    final onlyUnknown = missing > 0 && summary?['pricedJobs'] == 0;
    return Scaffold(
        backgroundColor: AppColors.darkBg,
        body: SafeArea(
            child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(children: [
                if (Navigator.canPop(context))
                  IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.white)),
                Text('Earnings',
                    style: GoogleFonts.syne(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const Spacer(),
                IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
              ])),
          Expanded(
              child: RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView(
                      padding: const EdgeInsets.all(16),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        DropdownButton<String>(
                            value: _period,
                            items: ['All Time', 'This Month', 'This Year']
                                .map((p) =>
                                    DropdownMenuItem(value: p, child: Text(p)))
                                .toList(),
                            onChanged: (p) {
                              if (p != null) {
                                setState(() => _period = p);
                                _reload();
                              }
                            }),
                        if (_history.loading) const LinearProgressIndicator(),
                        if (_history.error != null) ...[
                          Text(_history.error!,
                              style:
                                  const TextStyle(color: AppColors.darkError)),
                          TextButton(
                              onPressed: _reload, child: const Text('Retry'))
                        ],
                        Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF1A3A6B),
                                      Color(0xFF2563EB)
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight),
                                borderRadius: BorderRadius.circular(20)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Calculated Net (Booked)',
                                      style: TextStyle(color: Colors.white70)),
                                  Text(
                                      pkr(onlyUnknown
                                          ? null
                                          : summary?['netMinor']),
                                      style: GoogleFonts.syne(
                                          fontSize: 30,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white)),
                                  const Text(
                                      'Payment occurs outside OnRaasta. These are calculated amounts, not confirmed cash received or payouts.',
                                      style: TextStyle(color: Colors.white70)),
                                ])),
                        const SizedBox(height: 16),
                        Row(children: [
                          Expanded(
                              child: _SummaryCard(
                                  label: 'Gross Booked',
                                  value: pkr(onlyUnknown
                                      ? null
                                      : summary?['grossMinor']),
                                  icon: Icons.receipt_long,
                                  iconColor: AppColors.darkSuccess)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _SummaryCard(
                                  label: 'Commission (15%)',
                                  value: pkr(onlyUnknown
                                      ? null
                                      : summary?['commissionMinor']),
                                  icon: Icons.percent,
                                  iconColor: AppColors.darkAccent))
                        ]),
                        if (summary != null)
                          Text(
                              'Completed jobs: ${summary['completedJobs']} | Priced: ${summary['pricedJobs']}',
                              style: const TextStyle(
                                  color: AppColors.darkTextSecondary)),
                        if (missing > 0)
                          Text(
                              '$missing completed job(s) have unavailable pricing. Totals include priced jobs only.',
                              style: const TextStyle(
                                  color: AppColors.darkWarning)),
                        if (_history.undated > 0)
                          Text(
                              '${_history.undated} completed job(s) have no completion date; dated filters cannot place them.',
                              style: const TextStyle(
                                  color: AppColors.darkWarning)),
                        TextButton(
                            onPressed: () => context.push('/mechanic-history'),
                            child: const Text('View Assigned Job History')),
                        if (summary != null) ...[
                          const Text('MONTHLY BOOKED NET (UTC)',
                              style: TextStyle(
                                  color: AppColors.darkTextSecondary)),
                          if (summary['moreMonths'] == true)
                            const Text(
                                'Showing the latest 24 months. Select a period to narrow the report.',
                                style: TextStyle(
                                    color: AppColors.darkTextSecondary)),
                          for (final raw in summary['months'] as List? ?? [])
                            Builder(builder: (_) {
                              final m = objectMap(raw);
                              return ListTile(
                                  title: Text(m['month'] as String? ?? ''),
                                  subtitle: Text(
                                      '${m['completedJobs']} completed, ${m['unpricedJobs']} unpriced'),
                                  trailing: Text(pkr(m['pricedJobs'] == 0 &&
                                          (m['unpricedJobs'] as int? ?? 0) > 0
                                      ? null
                                      : m['netMinor'])));
                            }),
                        ],
                        const Text('COMPLETED JOB BREAKDOWN',
                            style:
                                TextStyle(color: AppColors.darkTextSecondary)),
                        if (!_history.loading &&
                            _history.jobs.isEmpty &&
                            summary != null)
                          const Text('No completed jobs in this period.',
                              style: TextStyle(
                                  color: AppColors.darkTextSecondary)),
                        for (final job in _history.jobs)
                          HistoryJobCard(
                              job: job,
                              service: _history.service,
                              mechanic: true),
                        if (_history.hasMore)
                          TextButton(
                              onPressed: _history.loading
                                  ? null
                                  : () => _history.load(more: true),
                              child: const Text('Load More')),
                      ]))),
        ])));
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 10),
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 12, color: const Color(0xFF94A3B8))),
          const SizedBox(height: 2),
          Text(value,
              style: GoogleFonts.syne(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ],
      ),
    );
  }
}

// ── Transaction row ───────────────────────────────────────────────────────────
