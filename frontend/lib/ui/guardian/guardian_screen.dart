// lib/ui/guardian/guardian_screen.dart
// Full Guardian Link management screen.
// Reached via the shield icon in the AppBar of MainShell.
//
// States:
//   1. No guardian linked  → show link form
//   2. Guardian linked     → show guardian card + notify button + latest report
//
// Features:
//   - Link a guardian by phone number (Kenyan format supported)
//   - Unlink with confirmation dialog
//   - Manual notify button (no cooldown) — reruns analysis and sends report
//   - Latest report viewer (the exact text sent to the guardian)
//   - Explanation of auto-notify triggers so student understands the feature

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../providers/guardian_provider.dart';
import '../../providers/auth_provider.dart';

class GuardianScreen extends StatefulWidget {
  const GuardianScreen({super.key});

  @override
  State<GuardianScreen> createState() => _GuardianScreenState();
}

class _GuardianScreenState extends State<GuardianScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<GuardianProvider>();
      provider.fetchStatus();
      provider.fetchLatestReport();
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  // ─── Link ─────────────────────────────────────────────────────────────────
  Future<void> _linkGuardian() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<GuardianProvider>();
    final success =
        await provider.linkGuardian(_phoneController.text.trim());

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? provider.successMessage ?? 'Guardian linked.'
            : provider.errorMessage ?? 'Failed to link guardian.'),
        backgroundColor: success ? AppTheme.success : AppTheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );

    if (success) {
      _phoneController.clear();
      provider.clearMessages();
    }
  }

  // ─── Unlink ───────────────────────────────────────────────────────────────
  Future<void> _unlinkGuardian() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlink Guardian'),
        content: const Text(
            'Your guardian will stop receiving notifications. '
            'You can re-link them at any time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final provider = context.read<GuardianProvider>();
    final success = await provider.unlinkGuardian();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? 'Guardian unlinked successfully.'
            : provider.errorMessage ?? 'Failed to unlink guardian.'),
        backgroundColor: success ? AppTheme.success : AppTheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    provider.clearMessages();
  }

  // ─── Manual Notify ────────────────────────────────────────────────────────
  Future<void> _notifyGuardian() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send Report to Guardian'),
        content: const Text(
            'This will run a fresh financial analysis and send '
            'the results to your guardian now.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send Now'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final provider = context.read<GuardianProvider>();
    final now = DateTime.now();
    final success = await provider.notifyGuardian(
      month: now.month,
      year: now.year,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? provider.successMessage ?? 'Guardian notified.'
            : provider.errorMessage ?? 'Notification failed.'),
        backgroundColor: success ? AppTheme.success : AppTheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );

    if (success) {
      // Refresh latest report after sending.
      provider.fetchLatestReport();
      provider.clearMessages();
    }
  }

  @override
  Widget build(BuildContext context) {
    final guardian = context.watch<GuardianProvider>();
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guardian Link'),
        actions: [
          if (guardian.isLinked)
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'Refresh',
              onPressed: () {
                guardian.fetchStatus();
                guardian.fetchLatestReport();
              },
            ),
        ],
      ),
      backgroundColor: AppTheme.background,
      body: guardian.isLoading && !guardian.isLinked
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: () async {
                await guardian.fetchStatus();
                await guardian.fetchLatestReport();
              },
              color: AppTheme.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Feature explainer ──────────────────────────────────
                    _buildExplainer(),

                    const SizedBox(height: 20),

                    // ── State: not linked / linked ─────────────────────────
                    if (!guardian.isLinked)
                      _buildLinkForm(guardian)
                    else
                      _buildLinkedView(guardian, auth.user?.username ?? ''),

                    const SizedBox(height: 24),

                    // ── Auto-notify triggers info ──────────────────────────
                    _buildTriggersInfo(),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  // ─── Explainer Banner ─────────────────────────────────────────────────────
  Widget _buildExplainer() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            children: [
              Icon(Icons.shield_outlined,
                  size: 18, color: AppTheme.primary),
              SizedBox(width: 8),
              Text(
                'What is Guardian Link?',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Guardian Link lets you connect a trusted person (parent, '
            'guardian, or mentor) who receives WhatsApp/SMS reports '
            'about your financial health. This is optional and you '
            'remain in full control of your finances.',
            style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.4),
          ),
        ],
      ),
    );
  }

  // ─── Link Form (no guardian yet) ─────────────────────────────────────────
  Widget _buildLinkForm(GuardianProvider provider) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Link a Guardian',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Enter their phone number. They will receive reports '
              'via WhatsApp, or SMS if WhatsApp is unavailable.',
              style:
                  TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),

            const SizedBox(height: 18),

            // Phone number field
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                    RegExp(r'[\d\+\-\s]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Guardian Phone Number',
                hintText: '0712 345 678 or +254712345678',
                prefixIcon: Icon(Icons.phone_outlined),
                helperText:
                    'Kenyan numbers (07XX) are accepted — country code added automatically.',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a phone number.';
                }
                final digits =
                    value.replaceAll(RegExp(r'[\s\-\+]'), '');
                if (digits.length < 9) {
                  return 'Please enter a valid phone number.';
                }
                return null;
              },
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: provider.isLoading ? null : _linkGuardian,
                icon: provider.isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.link),
                label: Text(
                    provider.isLoading ? 'Linking...' : 'Link Guardian'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Linked View (guardian is active) ────────────────────────────────────
  Widget _buildLinkedView(GuardianProvider provider, String username) {
    final guardian = provider.guardian!;
    final lastNotifiedFmt = guardian.lastNotified != null
        ? DateFormat('dd MMM yyyy, hh:mm a')
            .format(DateTime.parse(guardian.lastNotified!).toLocal())
        : 'Never';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Guardian card ────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: AppTheme.success.withOpacity(0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.shield,
                        color: AppTheme.success, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Guardian Active',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.success,
                          ),
                        ),
                        Text(
                          guardian.phoneNumber,
                          style: const TextStyle(
                              fontSize: 14,
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  // Unlink button
                  IconButton(
                    onPressed: _unlinkGuardian,
                    icon: const Icon(Icons.link_off,
                        color: AppTheme.error, size: 22),
                    tooltip: 'Unlink Guardian',
                  ),
                ],
              ),

              const Divider(height: 24),

              // Last notified
              Row(
                children: [
                  const Icon(Icons.notifications_outlined,
                      size: 15, color: AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    'Last notified: $lastNotifiedFmt',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Manual notify button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed:
                      provider.isLoading ? null : _notifyGuardian,
                  icon: provider.isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_outlined),
                  label: Text(provider.isLoading
                      ? 'Sending...'
                      : 'Send Report Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.info,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Latest Report ────────────────────────────────────────────────
        _buildLatestReport(provider),
      ],
    );
  }

  // ─── Latest Report Viewer ─────────────────────────────────────────────────
  Widget _buildLatestReport(GuardianProvider provider) {
    final report = provider.latestReport;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Latest Report Sent',
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 10),

        if (report == null)
          const Text(
            'No reports sent yet. Tap "Send Report Now" to send your first one.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Report metadata
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: report.trigger == 'auto'
                            ? AppTheme.warning.withOpacity(0.1)
                            : AppTheme.info.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        report.trigger == 'auto'
                            ? 'Auto-triggered'
                            : 'Manually sent',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: report.trigger == 'auto'
                              ? AppTheme.warning
                              : AppTheme.info,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color:
                            AppTheme.scoreColor(_scoreToCategory(report.score))
                                .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Score: ${report.score}/100',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.scoreColor(
                              _scoreToCategory(report.score)),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      DateFormat('dd MMM, hh:mm a').format(
                          DateTime.parse(report.createdAt).toLocal()),
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ],
                ),

                const Divider(height: 16),

                // Report text — exact message sent to guardian
                Text(
                  report.reportText,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textPrimary,
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ─── Auto-notify Triggers Explainer ──────────────────────────────────────
  Widget _buildTriggersInfo() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline,
                  size: 16, color: AppTheme.textSecondary),
              SizedBox(width: 8),
              Text(
                'When is your guardian auto-notified?',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _triggerRow(
            icon: Icons.warning_amber_outlined,
            color: AppTheme.error,
            text: 'Your financial score drops below 40 (Critical)',
          ),
          _triggerRow(
            icon: Icons.trending_down,
            color: AppTheme.error,
            text: 'Your spending trend is worsening rapidly',
          ),
          _triggerRow(
            icon: Icons.calendar_today_outlined,
            color: AppTheme.warning,
            text:
                'More than 80% of income spent before mid-month',
          ),
          const SizedBox(height: 8),
          const Text(
            'Auto-notifications have a 24-hour cooldown to prevent spam. '
            'Manual notifications (above) can be sent at any time.',
            style: TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
                height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _triggerRow({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
          ),
        ],
      ),
    );
  }

  // ─── Helper ───────────────────────────────────────────────────────────────
  String _scoreToCategory(int score) {
    if (score >= 90) return 'Elite';
    if (score >= 80) return 'Excellent';
    if (score >= 70) return 'Very Good';
    if (score >= 60) return 'Good';
    if (score >= 50) return 'Average';
    if (score >= 40) return 'At Risk';
    return 'Critical';
  }
}