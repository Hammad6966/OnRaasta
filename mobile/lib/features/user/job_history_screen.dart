import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/history_job_card.dart';
import '../../providers/history_controller.dart';
import '../../services/history_service.dart';

class JobHistoryScreen extends StatefulWidget {
  const JobHistoryScreen({super.key, this.mechanic = false, this.service});
  final bool mechanic;
  final HistoryService? service;
  @override
  State<JobHistoryScreen> createState() => _JobHistoryScreenState();
}

class _JobHistoryScreenState extends State<JobHistoryScreen>
    with WidgetsBindingObserver {
  late final HistoryController _history;
  int _filter = 0;
  static const labels = ['All', 'Active', 'Completed', 'Cancelled'];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _history =
        HistoryController(service: widget.service, mechanic: widget.mechanic)
          ..addListener(_changed);
    _history.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _history.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _history.removeListener(_changed);
    _history.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              if (Navigator.canPop(context))
                IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white)),
              Text(widget.mechanic ? 'Assigned Job History' : 'Job History',
                  style: const TextStyle(
                      fontFamily: 'Syne',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const Spacer(),
              IconButton(
                  onPressed: () => _history.load(),
                  icon: const Icon(Icons.refresh,
                      color: AppColors.darkTextSecondary)),
            ])),
        SizedBox(
            height: 52,
            child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                            label: Text(labels[i]),
                            selected: _filter == i,
                            selectedColor: AppColors.darkPrimary,
                            backgroundColor: AppColors.darkSurface,
                            onSelected: (_) {
                              setState(() => _filter = i);
                              _history.filter(
                                  status:
                                      i == 0 ? null : labels[i].toLowerCase());
                            })),
                ])),
        if (_history.loading) const LinearProgressIndicator(),
        if (_history.error != null)
          Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Text(_history.error!,
                    style: const TextStyle(color: AppColors.darkError)),
                TextButton(
                    onPressed: () => _history.load(),
                    child: const Text('Retry'))
              ])),
        Expanded(
            child: RefreshIndicator(
                onRefresh: () => _history.load(),
                child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      if (!_history.loading &&
                          _history.jobs.isEmpty &&
                          _history.error == null)
                        const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(
                                child: Text('No jobs found',
                                    style: TextStyle(
                                        color: AppColors.darkTextSecondary)))),
                      for (final job in _history.jobs)
                        HistoryJobCard(
                            job: job,
                            service: _history.service,
                            mechanic: widget.mechanic),
                      if (_history.hasMore)
                        TextButton(
                            onPressed: _history.loading
                                ? null
                                : () => _history.load(more: true),
                            child: const Text('Load More')),
                    ]))),
      ])));
}
