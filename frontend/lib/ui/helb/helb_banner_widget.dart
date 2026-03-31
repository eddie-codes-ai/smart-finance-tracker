// lib/ui/helb/helb_banner_widget.dart
//
// Dashboard banner card for the HELB Semester Planner.
// - If NO plan exists  → shows a "Set Up Plan" prompt card.
// - If a plan exists   → shows full card: school icon, semester name,
//                        days progress bar, day counter + KES amount.
// Tapping either state navigates to HelbPlannerScreen.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:frontend/core/helb_storage.dart';
import 'package:frontend/core/routes.dart';

class HelbBannerWidget extends StatefulWidget {
  const HelbBannerWidget({super.key});

  @override
  State<HelbBannerWidget> createState() => _HelbBannerWidgetState();
}

class _HelbBannerWidgetState extends State<HelbBannerWidget> {
  HelbPlan? _plan;
  bool _checked = false;

  final _fmt = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }

  Future<void> _loadPlan() async {
    final plan = await HelbStorage.loadPlan();
    if (mounted) {
      setState(() {
        _plan = plan;
        _checked = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) return const SizedBox.shrink();

    // ── No plan yet — prompt card ─────────────────────────────────────────
    if (_plan == null) {
      return GestureDetector(
        onTap: () => Navigator.pushNamed(context, AppRoutes.helbPlanner),
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.school_outlined,
                    size: 20,
                    color: Colors.blue.shade600,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HELB Semester Planner',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Tap to ration your HELB across the semester',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              ],
            ),
          ),
        ),
      );
    }

    // ── Plan exists — progress card ───────────────────────────────────────
    final plan         = _plan!;
    final daysProgress = plan.progressFraction.clamp(0.0, 1.0);
    final Color progressColor =
        daysProgress > 0.9 ? Colors.orange.shade600 : Colors.blue.shade500;

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRoutes.helbPlanner),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title row ───────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.school_outlined,
                      size: 18,
                      color: Colors.blue.shade600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.semesterName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          'HELB Semester Planner',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${plan.daysRemaining} days left',
                    style: TextStyle(
                      fontSize: 12,
                      color: plan.daysRemaining < 14
                          ? Colors.orange.shade700
                          : Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Colors.grey,
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // ── Progress bar ─────────────────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: daysProgress,
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(progressColor),
                ),
              ),

              const SizedBox(height: 8),

              // ── Footer row ───────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Day ${plan.daysElapsed} of ${plan.totalDays}'
                    '  (${(daysProgress * 100).toStringAsFixed(0)}%)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    'KES ${_fmt.format(plan.helbAmount)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}