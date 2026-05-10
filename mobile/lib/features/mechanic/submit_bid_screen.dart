import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/onraasta_input.dart';
import '../../core/constants/api_constants.dart';
import 'mechanic_home_screen.dart';

class SubmitBidScreen extends StatefulWidget {
  final Map<String, dynamic> job;

  const SubmitBidScreen({super.key, required this.job});

  @override
  State<SubmitBidScreen> createState() => _SubmitBidScreenState();
}

class _SubmitBidScreenState extends State<SubmitBidScreen> {
  final _formKey = GlobalKey<FormState>();
  final _labourController = TextEditingController();
  final _partsController  = TextEditingController();
  final _etaController    = TextEditingController();

  bool _isSubmitting = false;

  // Derived values
  int _labour     = 0;
  int _parts      = 0;
  int _total      = 0;
  int _commission = 0;
  int _earnings   = 0;

  @override
  void dispose() {
    _labourController.dispose();
    _partsController.dispose();
    _etaController.dispose();
    super.dispose();
  }

  void _recalculate() {
    final l = int.tryParse(_labourController.text) ?? 0;
    final p = int.tryParse(_partsController.text) ?? 0;
    final t = l + p;
    setState(() {
      _labour     = l;
      _parts      = p;
      _total      = t;
      _commission = (t * 0.15).round();
      _earnings   = t - (t * 0.15).round();
    });
  }

  Future<void> _submitBid() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final storage = const FlutterSecureStorage();
      final token = await storage.read(key: 'access_token');
      if (token == null || token.isEmpty) {
        if (!mounted) return;
        context.go('/login');
        return;
      }

      final jobId = widget.job['_id'] as String? ??
          widget.job['jobId'] as String? ?? '';

      final dio = Dio(BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ));

      await dio.post('/bids', data: {
        'jobId':      jobId,
        'labourCost': _labour,
        'partsCost':  _parts,
        'totalCost':  _total,
        'eta':        int.tryParse(_etaController.text) ?? 30,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bid submitted successfully!'),
          backgroundColor: AppColors.darkSuccess,
          duration: Duration(seconds: 3),
        ),
      );

      // Pop twice: back to mechanic home (past new_request_detail)
      context.pop();
      context.pop();
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = (e.response?.data as Map?)?['message'] as String? ??
          'Failed to submit bid. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.darkError,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = JobRequest.fromJson(widget.job);

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.darkSurface,
                        border: Border.all(color: AppColors.darkBorder),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Submit Bid',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Syne',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Job summary chip ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.darkSurface,
                  border: Border.all(color: AppColors.darkBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.work_outline_rounded,
                        color: AppColors.darkPrimary, size: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        request.description,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'DM Sans',
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${request.distance.toStringAsFixed(1)} km',
                      style: const TextStyle(
                        color: AppColors.darkTextSecondary,
                        fontFamily: 'DM Sans',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Form ─────────────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Labour cost
                      OnRaastaInput(
                        controller: _labourController,
                        label: 'Labour Cost (PKR)',
                        hint: 'Minimum 500',
                        keyboardType: TextInputType.number,
                        prefixIcon: const Icon(Icons.build_rounded,
                            color: AppColors.darkTextSecondary, size: 18),
                        onChanged: (_) => _recalculate(),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          if (n == null || n < 500) {
                            return 'Minimum labour cost is PKR 500';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      // Parts cost
                      OnRaastaInput(
                        controller: _partsController,
                        label: 'Parts Cost (PKR)',
                        hint: '0 if no parts needed',
                        keyboardType: TextInputType.number,
                        prefixIcon: const Icon(Icons.settings_rounded,
                            color: AppColors.darkTextSecondary, size: 18),
                        onChanged: (_) => _recalculate(),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          if (v != null && v.isNotEmpty && n == null) {
                            return 'Enter a valid amount';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      // ETA
                      OnRaastaInput(
                        controller: _etaController,
                        label: 'ETA (minutes)',
                        hint: 'Estimated arrival time',
                        keyboardType: TextInputType.number,
                        prefixIcon: const Icon(Icons.timer_rounded,
                            color: AppColors.darkTextSecondary, size: 18),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          if (n == null || n < 1) {
                            return 'Enter a valid ETA in minutes';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 24),

                      // ── Cost breakdown card ──────────────────────────────────
                      if (_total > 0) ...[
                        _CostBreakdown(
                          labour:     _labour,
                          parts:      _parts,
                          total:      _total,
                          commission: _commission,
                          earnings:   _earnings,
                        ),
                        const SizedBox(height: 24),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // ── Submit button ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              decoration: const BoxDecoration(
                color: AppColors.darkSurface,
                border: Border(top: BorderSide(color: AppColors.darkBorder)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitBid,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.darkPrimary,
                    disabledBackgroundColor:
                        AppColors.darkPrimary.withOpacity(0.5),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.gavel_rounded,
                                color: Colors.white, size: 20),
                            SizedBox(width: 10),
                            Text(
                              'Submit Bid',
                              style: TextStyle(
                                color: Colors.white,
                                fontFamily: 'DM Sans',
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Cost breakdown widget ─────────────────────────────────────────────────────

class _CostBreakdown extends StatelessWidget {
  final int labour;
  final int parts;
  final int total;
  final int commission;
  final int earnings;

  const _CostBreakdown({
    required this.labour,
    required this.parts,
    required this.total,
    required this.commission,
    required this.earnings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        border: Border.all(color: AppColors.darkBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long_rounded,
                  color: AppColors.darkPrimary, size: 16),
              SizedBox(width: 8),
              Text(
                'Cost Breakdown',
                style: TextStyle(
                  color: AppColors.darkTextSecondary,
                  fontFamily: 'DM Sans',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          _BreakdownRow(label: 'Labour',   value: labour,     color: Colors.white),
          const SizedBox(height: 8),
          _BreakdownRow(label: 'Parts',    value: parts,      color: Colors.white),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(color: AppColors.darkBorder, height: 1),
          ),

          _BreakdownRow(label: 'Total',    value: total,      color: Colors.white,         bold: true),
          const SizedBox(height: 8),
          _BreakdownRow(
            label: 'Platform Fee (15%)',
            value: commission,
            color: AppColors.darkError,
          ),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(color: AppColors.darkBorder, height: 1),
          ),

          // Earnings highlight
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.darkSuccess.withOpacity(0.1),
              border: Border.all(color: AppColors.darkSuccess.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Your Earnings',
                  style: TextStyle(
                    color: AppColors.darkSuccess,
                    fontFamily: 'DM Sans',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'PKR ${earnings.toString()}',
                  style: const TextStyle(
                    color: AppColors.darkSuccess,
                    fontFamily: 'Syne',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final bool bold;

  const _BreakdownRow({
    required this.label,
    required this.value,
    required this.color,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: bold ? Colors.white : AppColors.darkTextSecondary,
            fontFamily: 'DM Sans',
            fontSize: bold ? 14 : 13,
            fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        Text(
          'PKR $value',
          style: TextStyle(
            color: color,
            fontFamily: 'DM Sans',
            fontSize: bold ? 14 : 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
