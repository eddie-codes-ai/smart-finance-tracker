// lib/ui/transactions/mpesa_import_screen.dart
//
// Two-tab screen for importing M-Pesa transactions:
//
//   Tab 1 — From SMS inbox
//     Requests READ_SMS permission on first open.
//     Loads the last 60 M-Pesa messages from the phone's inbox.
//     Student taps any message → it is parsed and the result card appears.
//
//   Tab 2 — Paste message
//     Large text area where the student pastes a copied M-Pesa SMS.
//     "Parse message" button → same result card appears.
//
//   Shared result card (shown in a bottom sheet for both tabs):
//     Shows all parsed fields — amount, description, category, type.
//     Student can edit description and change the category before saving.
//     "From memory" badge shown when category came from MpesaMemory.
//     On save → calls ExpenseProvider.addExpense() or IncomeProvider.addIncome()
//     Also calls MpesaMemory.save() to update the memory.
//
// CHANGE: Income type section is now selectable chips instead of a static
// display box. The parser's suggestion is pre-selected but the user can
// tap any chip to override before saving.

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:provider/provider.dart';

import '../../core/mpesa_parser.dart';
import '../../core/category_suggester.dart';
import '../../core/mpesa_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../providers/expense_provider.dart';
import '../../providers/income_provider.dart';

class MpesaImportScreen extends StatefulWidget {
  const MpesaImportScreen({super.key});

  @override
  State<MpesaImportScreen> createState() => _MpesaImportScreenState();
}

class _MpesaImportScreenState extends State<MpesaImportScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tabController;

  // ── SMS tab state ─────────────────────────────────────────────────────────
  bool _smsPermissionGranted = false;
  bool _smsLoading            = false;
  List<SmsMessage> _smsList   = [];
  String? _smsError;

  // ── Paste tab state ───────────────────────────────────────────────────────
  final _pasteController = TextEditingController();

  // ── Shared: saving state ──────────────────────────────────────────────────
  bool _saving   = false;
  bool _autoSave = false;   // persisted in SharedPreferences

  static const _kAutoSaveKey = 'mpesa_auto_save_enabled';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkSmsPermission();
    _loadAutoSavePreference();
  }

  // ── Load/save auto-save preference ───────────────────────────────────────

  Future<void> _loadAutoSavePreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _autoSave = prefs.getBool(_kAutoSaveKey) ?? false;
      });
    }
  }

  Future<void> _setAutoSave(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoSaveKey, value);
    if (mounted) setState(() => _autoSave = value);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pasteController.dispose();
    super.dispose();
  }

  // ── Permission logic ──────────────────────────────────────────────────────

  Future<void> _checkSmsPermission() async {
    final status = await Permission.sms.status;
    if (status.isGranted) {
      setState(() => _smsPermissionGranted = true);
      _loadSmsMessages();
    }
  }

  Future<void> _requestSmsPermission() async {
    final status = await Permission.sms.request();
    if (status.isGranted) {
      setState(() => _smsPermissionGranted = true);
      _loadSmsMessages();
    } else {
      setState(() => _smsError =
          'SMS permission denied. Use the Paste tab instead, or grant the permission in your phone Settings.');
    }
  }

  // ── Load SMS messages ─────────────────────────────────────────────────────

  Future<void> _loadSmsMessages() async {
    setState(() {
      _smsLoading = true;
      _smsError   = null;
    });

    try {
      final query    = SmsQuery();
      final messages = await query.querySms(
        kinds: [SmsQueryKind.inbox],
      );

      // Filter to M-Pesa messages only (sender is "MPESA" on Safaricom)
      final mpesaMessages = messages.where((m) {
        final address = (m.address ?? '').toUpperCase();
        final body    = (m.body    ?? '').toUpperCase();
        return address.contains('MPESA') ||
               address.contains('M-PESA') ||
               (body.contains('CONFIRMED') && body.contains('KSH'));
      }).take(60).toList();

      setState(() {
        _smsList    = mpesaMessages;
        _smsLoading = false;
      });
    } catch (e) {
      setState(() {
        _smsError   = 'Could not read SMS messages: ${e.toString()}';
        _smsLoading = false;
      });
    }
  }

  // ── Parse & show result ───────────────────────────────────────────────────

  Future<void> _handleMessage(String rawMessage) async {
    final result = MpesaParser.parse(rawMessage);
    if (result == null) {
      _showError('This does not look like an M-Pesa message. '
          'Make sure you copy the full SMS including the transaction code.');
      return;
    }

    // Priority 1: memory lookup
    final remembered = await MpesaMemory.lookup(result.recipientOrSender);

    // Priority 2: keyword suggestion (only for expenses — income has no category)
    String finalCategory;
    bool   fromMemory = false;

    if (result.type == 'expense') {
      if (remembered != null) {
        finalCategory = remembered;
        fromMemory    = true;
      } else {
        finalCategory =
            CategorySuggester.suggest(result.description) ??
            result.suggestedCategory;
      }
    } else {
      finalCategory = 'Other';
    }

    if (!mounted) return;
    _showResultSheet(result, finalCategory, fromMemory);
  }


  // ── Auto-save (one-tap) ───────────────────────────────────────────────────
  // Called when auto-save toggle is ON and user taps a message.
  // If recipient is known in memory → saves instantly, no card shown.
  // If recipient is new → falls back to normal review card.
  Future<void> _handleMessageAutoSave(String rawMessage) async {
    final result = MpesaParser.parse(rawMessage);
    if (result == null) {
      _showError('Could not parse this M-Pesa message.');
      return;
    }

    final remembered = await MpesaMemory.lookup(result.recipientOrSender);

    if (result.type == 'expense' && remembered != null) {
      // Known recipient — save silently
      await _saveTransaction(
        result,
        remembered,
        result.description,
        result.incomeType,
      );
    } else {
      // New recipient or income — show review card once
      String finalCategory;
      bool fromMemory = false;
      if (result.type == 'expense') {
        finalCategory =
            CategorySuggester.suggest(result.description) ??
            result.suggestedCategory;
      } else {
        finalCategory = 'Other';
      }
      if (!mounted) return;
      _showResultSheet(result, finalCategory, fromMemory);
    }
  }

  // ── Result bottom sheet ───────────────────────────────────────────────────

  void _showResultSheet(
    MpesaParseResult result,
    String initialCategory,
    bool fromMemory,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ResultSheet(
        result:          result,
        initialCategory: initialCategory,
        fromMemory:      fromMemory,
        onSave:          _saveTransaction,
      ),
    );
  }

  // ── Save logic ────────────────────────────────────────────────────────────

  Future<void> _saveTransaction(
    MpesaParseResult result,
    String finalCategory,
    String finalDescription,
    String finalIncomeType, {
    bool fromSheet = false, // true = called from review card (needs 2 pops)
                            // false = called by auto-save directly (needs 1 pop)
  }) async {
    setState(() => _saving = true);

    try {
      if (result.type == 'expense') {
        await context.read<ExpenseProvider>().addExpense(
          amount:      result.amount,
          category:    finalCategory,
          description: finalDescription,
          expenseType: 'daily',
        );
        await MpesaMemory.save(result.recipientOrSender, finalCategory);
      } else {
        await context.read<IncomeProvider>().addIncome(
          amount:      result.amount,
          incomeType:  finalIncomeType,
          description: finalDescription,
        );
      }

      if (!mounted) return;

      if (fromSheet) {
        Navigator.pop(context); // close the review bottom sheet
      }
      Navigator.pop(context); // go back to transactions screen

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.type == 'expense'
                ? 'Expense of KES ${result.amount.toStringAsFixed(2)} saved.'
                : 'Income of KES ${result.amount.toStringAsFixed(2)} saved.',
          ),
          backgroundColor: AppTheme.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to save: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Error snackbar ────────────────────────────────────────────────────────

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import M-Pesa'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'From SMS inbox'),
            Tab(text: 'Paste message'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSmsTab(),
          _buildPasteTab(),
        ],
      ),
    );
  }

  // ── Tab 1: SMS inbox ──────────────────────────────────────────────────────

  Widget _buildSmsTab() {
    if (!_smsPermissionGranted) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.message_outlined, size: 56, color: Colors.grey),
            const SizedBox(height: 20),
            Text(
              'SMS permission needed',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'To read your M-Pesa messages automatically, the app needs '
              'permission to access your SMS inbox. Your messages are read '
              'locally on your device and never sent anywhere.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            if (_smsError != null) ...[
              Text(
                _smsError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
              const SizedBox(height: 16),
            ],
            ElevatedButton.icon(
              onPressed: _requestSmsPermission,
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('Allow SMS access'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => _tabController.animateTo(1),
              child: const Text('Use paste tab instead'),
            ),
          ],
        ),
      );
    }

    if (_smsLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_smsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_smsError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadSmsMessages,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    // Always show the toggle + content regardless of whether messages exist
    return Column(
      children: [
        // ── Auto-save toggle banner — always visible ──────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _autoSave
                ? AppTheme.primary.withOpacity(0.08)
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _autoSave
                  ? AppTheme.primary.withOpacity(0.3)
                  : Colors.grey.shade200,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _autoSave ? Icons.flash_on : Icons.flash_off_outlined,
                size: 18,
                color: _autoSave ? AppTheme.primary : Colors.grey,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _autoSave
                          ? 'One-tap import ON'
                          : 'One-tap import OFF',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _autoSave
                            ? AppTheme.primary
                            : AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      _autoSave
                          ? 'Known recipients save instantly. New ones still ask.'
                          : 'Tap a message to review before saving.',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _autoSave,
                onChanged: _setAutoSave,
                activeColor: AppTheme.primary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // ── Message list or empty state ───────────────────────────────────
        if (_smsList.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.inbox_outlined,
                      size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No M-Pesa messages found in your inbox.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Use the Paste tab to test with a sample message.',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => _tabController.animateTo(1),
                    child: const Text('Go to Paste tab'),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadSmsMessages,
              child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _smsList.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, index) {
                final sms  = _smsList[index];
                final body = sms.body ?? '';
                final amountMatch =
                    RegExp(r'[Kk]sh([\d,]+\.?\d*)').firstMatch(body);
                final preview = amountMatch != null
                    ? 'KES ${amountMatch.group(1)}'
                    : 'Tap to import';

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primary.withOpacity(0.15),
                    child: Icon(Icons.message, color: AppTheme.primary),
                  ),
                  title: Text(
                    body.length > 80
                        ? '${body.substring(0, 80)}...'
                        : body,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Row(
                    children: [
                      Text(
                        preview,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                      ),
                      if (sms.date != null) ...[
                        const Text('  ·  ',
                            style: TextStyle(color: Colors.grey)),
                        Text(
                          _formatDate(sms.date!),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                  onTap: () => _autoSave
                      ? _handleMessageAutoSave(body)
                      : _handleMessage(body),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // ── Tab 2: Paste ──────────────────────────────────────────────────────────

  Widget _buildPasteTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          // ── Auto-save toggle (same toggle, both tabs share _autoSave) ──────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _autoSave
                  ? AppTheme.primary.withOpacity(0.08)
                  : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _autoSave
                    ? AppTheme.primary.withOpacity(0.3)
                    : Colors.grey.shade200,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _autoSave ? Icons.flash_on : Icons.flash_off_outlined,
                  size: 18,
                  color: _autoSave ? AppTheme.primary : Colors.grey,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _autoSave
                            ? 'One-tap import ON'
                            : 'One-tap import OFF',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _autoSave
                              ? AppTheme.primary
                              : AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        _autoSave
                            ? 'Known recipients save without review card.'
                            : 'Always shows review card before saving.',
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _autoSave,
                  onChanged: _setAutoSave,
                  activeColor: AppTheme.primary,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Text(
            'Copy your M-Pesa confirmation SMS and paste it below.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Supported: send money, receive money, pay bill, buy goods, airtime.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pasteController,
            maxLines: 7,
            decoration: const InputDecoration(
              hintText:
                  'e.g.\nSB27LJ9O3R Confirmed. Ksh500.00 sent to JOHN KAMAU '
                  '0712345678 on 28/3/25 at 10:34 AM. New M-PESA balance is '
                  'Ksh1,450.00. Transaction cost, Ksh0.00.',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),

          // ── Memory status checker ──────────────────────────────────────────
          _MemoryStatusWidget(pasteController: _pasteController),

          const SizedBox(height: 12),

          ElevatedButton.icon(
            onPressed: _saving
                ? null
                : () {
                    final text = _pasteController.text.trim();
                    if (text.isEmpty) {
                      _showError('Please paste an M-Pesa message first.');
                      return;
                    }
                    // When auto-save is ON, use the auto-save path
                    if (_autoSave) {
                      _handleMessageAutoSave(text);
                    } else {
                      _handleMessage(text);
                    }
                  },
            icon: const Icon(Icons.auto_fix_high_outlined),
            label: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(_autoSave ? 'Import (auto-save)' : 'Parse message'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 24),
          _SampleHintCard(onTap: (sample) {
            _pasteController.text = sample;
          }),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatDate(DateTime d) {
    final now  = DateTime.now();
    final diff = now.difference(d);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7)  return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }
}


// ─── Result bottom sheet ─────────────────────────────────────────────────────

class _ResultSheet extends StatefulWidget {
  final MpesaParseResult result;
  final String           initialCategory;
  final bool             fromMemory;
  final Future<void> Function(
    MpesaParseResult result,
    String finalCategory,
    String finalDescription,
    String finalIncomeType, {
    bool fromSheet,
  }) onSave;

  const _ResultSheet({
    required this.result,
    required this.initialCategory,
    required this.fromMemory,
    required this.onSave,
  });

  @override
  State<_ResultSheet> createState() => _ResultSheetState();
}

class _ResultSheetState extends State<_ResultSheet> {
  late String _selectedCategory;
  late String _selectedIncomeType;        // ← NEW
  late TextEditingController _descController;
  bool _saving = false;

  // All 6 income types — matches INCOME_TYPES in models.py
  static const _incomeTypes = [
    'monthly', 'helb', 'parental', 'gig', 'daily', 'other',
  ];

  @override
  void initState() {
    super.initState();
    _selectedCategory  = widget.initialCategory;
    _selectedIncomeType = widget.result.incomeType;  // ← pre-select from parser
    _descController    = TextEditingController(text: widget.result.description);
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r         = widget.result;
    final isExpense = r.type == 'expense';

    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [

            // ── Header ─────────────────────────────────────────────────────
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: isExpense
                      ? Colors.red.shade50
                      : Colors.green.shade50,
                  child: Icon(
                    isExpense
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    color: isExpense ? Colors.red : AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isExpense ? 'Expense detected' : 'Income detected',
                        style: const TextStyle(
                            fontSize: 13, color: Colors.grey),
                      ),
                      Text(
                        'KES ${r.amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    r.transactionCode,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),

            // ── Description (editable) ─────────────────────────────────────
            Text('Description',
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 6),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),

            const SizedBox(height: 16),

            // ── Category chips (expenses only) ─────────────────────────────
            if (isExpense) ...[
              Row(
                children: [
                  Text('Category',
                      style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(width: 8),
                  if (widget.fromMemory)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppTheme.primary.withOpacity(0.4)),
                      ),
                      child: const Text(
                        'from memory',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: CategorySuggester.allCategories.map((cat) {
                  final selected = cat == _selectedCategory;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTheme.primary
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? AppTheme.primary
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Text(
                        cat,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: selected ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // ── Income type chips (income only) — UPDATED to be selectable ─
            if (!isExpense) ...[
              Text('Income type',
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _incomeTypes.map((type) {
                  final selected = type == _selectedIncomeType;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedIncomeType = type),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTheme.primary
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? AppTheme.primary
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Text(
                        type.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: selected ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // ── Save button ────────────────────────────────────────────────
            ElevatedButton.icon(
              onPressed: _saving
                  ? null
                  : () async {
                      setState(() => _saving = true);
                      await widget.onSave(
                        widget.result,
                        _selectedCategory,
                        _descController.text.trim(),
                        _selectedIncomeType,
                        fromSheet: true,
                      );
                      if (mounted) setState(() => _saving = false);
                    },
              icon: _saving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check),
              label: Text(_saving ? 'Saving...' : 'Save transaction'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),

            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}



// ─── Memory status widget ─────────────────────────────────────────────────────
// Shows whether the recipient in the pasted message is already in memory.
// Helps the user understand when auto-save will fire vs show the review card.

class _MemoryStatusWidget extends StatefulWidget {
  final TextEditingController pasteController;
  const _MemoryStatusWidget({required this.pasteController});

  @override
  State<_MemoryStatusWidget> createState() => _MemoryStatusWidgetState();
}

class _MemoryStatusWidgetState extends State<_MemoryStatusWidget> {
  String? _status;
  Color   _color = Colors.grey;

  @override
  void initState() {
    super.initState();
    widget.pasteController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.pasteController.removeListener(_onTextChanged);
    super.dispose();
  }

  Future<void> _onTextChanged() async {
    final text = widget.pasteController.text.trim();
    if (text.isEmpty) {
      if (mounted) setState(() => _status = null);
      return;
    }
    final result = MpesaParser.parse(text);
    if (result == null) {
      if (mounted) setState(() { _status = null; });
      return;
    }
    final remembered = await MpesaMemory.lookup(result.recipientOrSender);
    if (!mounted) return;
    setState(() {
      if (remembered != null) {
        _status = 'Memory: ${result.recipientOrSender} → $remembered (auto-save will fire)';
        _color  = AppTheme.primary;
      } else {
        _status = 'New recipient: ${result.recipientOrSender} (review card will show once)';
        _color  = AppTheme.warning;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_status == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            _color == AppTheme.primary
                ? Icons.memory
                : Icons.person_add_outlined,
            size: 14,
            color: _color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _status!,
              style: TextStyle(
                fontSize: 11,
                color: _color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sample hint card (paste tab) ────────────────────────────────────────────

class _SampleHintCard extends StatelessWidget {
  final void Function(String sample) onTap;

  const _SampleHintCard({required this.onTap});

  static const _samples = {
    'Send money':
        'SB27LJ9O3R Confirmed. Ksh500.00 sent to JOHN KAMAU 0712345678 on 28/3/25 at 10:34 AM. New M-PESA balance is Ksh1,450.00. Transaction cost, Ksh0.00.',
    'Receive money':
        'SB27LJ9O3R Confirmed. You have received Ksh3,500.00 from MARY WANJIRU 0723456789 on 28/3/25 at 9:12 AM. New M-PESA balance is Ksh4,950.00.',
    'Pay bill':
        'SB27LJ9O3R Confirmed. Ksh2,000.00 paid to KENYA POWER Account Number 12345678 on 28/3/25 at 8:00 AM. New M-PESA balance is Ksh800.00. Transaction cost, Ksh0.00.',
    'Buy goods':
        'SB27LJ9O3R Confirmed. Ksh250.00 paid to NAIVAS SUPERMARKET. on 28/3/25 at 2:15 PM. New M-PESA balance is Ksh1,200.00. Transaction cost, Ksh0.00.',
    'Airtime':
        'SB27LJ9O3R Confirmed. Ksh50.00 airtime bought successfully for 0712345678 on 28/3/25 at 11:05 AM. New M-PESA balance is Ksh750.00.',
    'HELB':
        'SB27LJ9O3R Confirmed. You have received Ksh15,000.00 from HELB 0800720765 on 28/3/25 at 7:30 AM. New M-PESA balance is Ksh15,000.00.',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Try a sample message',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _samples.entries.map((e) {
              return GestureDetector(
                onTap: () => onTap(e.value),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(e.key,
                      style: const TextStyle(fontSize: 12)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}