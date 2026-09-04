// lib/ui/transactions/mpesa_import_screen.dart
// UPDATED: Full dark mode support — auto-save banner, sample hint card,
// result sheet category chips all use theme-aware colors.

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:provider/provider.dart';

import '../../core/mpesa_parser.dart';
import '../../core/category_suggester.dart';
import '../../core/mpesa_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../data/remote/api_client.dart';
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
  bool _smsPermissionGranted = false;
  bool _smsLoading            = false;
  List<SmsMessage> _smsList   = [];
  String? _smsError;
  final _pasteController = TextEditingController();
  bool _saving   = false;
  bool _autoSave = false;
  static const _kAutoSaveKey = 'mpesa_auto_save_enabled';

  /// Transaction codes already in this account, so the list can mark them.
  /// Without this the only way to discover a message was already imported was
  /// to tap it and be refused.
  Set<String> _importedCodes = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkSmsPermission();
    _loadAutoSavePreference();
  }

  Future<void> _loadAutoSavePreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _autoSave = prefs.getBool(_kAutoSaveKey) ?? false);
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

  Future<void> _loadSmsMessages() async {
    setState(() { _smsLoading = true; _smsError = null; });
    try {
      final query    = SmsQuery();
      final messages = await query.querySms(kinds: [SmsQueryKind.inbox]);
      final mpesaMessages = messages.where((m) {
        final address = (m.address ?? '').toUpperCase();
        final body    = (m.body    ?? '').toUpperCase();
        return address.contains('MPESA') || address.contains('M-PESA') ||
               (body.contains('CONFIRMED') && body.contains('KSH'));
      }).take(60).toList();
      setState(() { _smsList = mpesaMessages; _smsLoading = false; });
      await _loadImportedCodes(mpesaMessages);
    } catch (e) {
      setState(() { _smsError = 'Could not read SMS messages: ${e.toString()}'; _smsLoading = false; });
    }
  }

  /// One round trip for the whole visible list, rather than a request per row.
  Future<void> _loadImportedCodes(List<SmsMessage> messages) async {
    final codes = <String>{};
    for (final m in messages) {
      final parsed = MpesaParser.parse(m.body ?? '');
      final code   = parsed?.transactionCode;
      if (code != null && code.isNotEmpty && code != 'N/A') codes.add(code);
    }
    if (codes.isEmpty) return;
    try {
      final data = await ApiClient.checkImportedMpesaCodes(codes.toList());
      final imported = (data['imported'] as List).cast<String>().toSet();
      if (mounted) setState(() => _importedCodes = imported);
    } catch (_) {
      // Not being able to mark them is a cosmetic loss; the server still
      // refuses a duplicate on save, so nothing can slip through.
    }
  }

  /// The date to file an imported transaction under.
  ///
  /// The SMS envelope's timestamp is authoritative when importing from the
  /// inbox. Pasted text has no envelope, so the date inside the message body is
  /// the next best thing, and "now" is the last resort.
  DateTime _resolveDate(MpesaParseResult result, DateTime? smsDate) {
    return smsDate ?? result.transactionDate ?? DateTime.now();
  }

  Future<void> _handleMessage(String rawMessage, {DateTime? smsDate}) async {
    final result = MpesaParser.parse(rawMessage);
    if (result == null) {
      _showError('This does not look like an M-Pesa message. Make sure you copy the full SMS including the transaction code.');
      return;
    }
    final remembered = await MpesaMemory.lookup(result.recipientOrSender);
    String finalCategory; bool fromMemory = false;
    if (result.type == 'expense') {
      if (remembered != null) { finalCategory = remembered; fromMemory = true; }
      else { finalCategory = CategorySuggester.suggest(result.description) ?? result.suggestedCategory; }
    } else { finalCategory = 'Other'; }
    if (!mounted) return;
    _showResultSheet(result, finalCategory, fromMemory, _resolveDate(result, smsDate));
  }

  Future<void> _handleMessageAutoSave(String rawMessage, {DateTime? smsDate}) async {
    final result = MpesaParser.parse(rawMessage);
    if (result == null) { _showError('Could not parse this M-Pesa message.'); return; }
    final remembered = await MpesaMemory.lookup(result.recipientOrSender);
    if (result.type == 'expense' && remembered != null) {
      await _saveTransaction(result, remembered, result.description,
          result.incomeType, _resolveDate(result, smsDate));
    } else {
      String finalCategory; bool fromMemory = false;
      if (result.type == 'expense') {
        finalCategory = CategorySuggester.suggest(result.description) ?? result.suggestedCategory;
      } else { finalCategory = 'Other'; }
      if (!mounted) return;
      _showResultSheet(result, finalCategory, fromMemory, _resolveDate(result, smsDate));
    }
  }

  void _showResultSheet(MpesaParseResult result, String initialCategory,
      bool fromMemory, DateTime transactionDate) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ResultSheet(
          result: result, initialCategory: initialCategory,
          fromMemory: fromMemory, transactionDate: transactionDate,
          onSave: _saveTransaction),
    );
  }

  Future<void> _saveTransaction(
    MpesaParseResult result, String finalCategory,
    String finalDescription, String finalIncomeType, DateTime transactionDate,
    {bool fromSheet = false}) async {
    setState(() => _saving = true);

    // Captured before any await, so the snackbar and pops do not reach for a
    // context that may no longer be mounted.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final expenses  = context.read<ExpenseProvider>();
    final incomes   = context.read<IncomeProvider>();

    // "N/A" means the parser found no code; sending it would make every
    // unparseable message collide with the first one.
    final code = result.transactionCode == 'N/A' ? null : result.transactionCode;

    final bool saved;
    final String? failure;
    if (result.type == 'expense') {
      saved = await expenses.addExpense(
          amount: result.amount, category: finalCategory,
          description: finalDescription, expenseType: 'daily',
          mpesaCode: code, dateAdded: transactionDate);
      failure = expenses.errorMessage;
      if (saved) await MpesaMemory.save(result.recipientOrSender, finalCategory);
    } else {
      saved = await incomes.addIncome(
          amount: result.amount, incomeType: finalIncomeType,
          description: finalDescription,
          mpesaCode: code, dateAdded: transactionDate);
      failure = incomes.errorMessage;
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (!saved) {
      // Nothing was written. Say so rather than reporting a save that did not
      // happen - a duplicate import reads as information, not an error.
      if (fromSheet) navigator.pop();
      messenger.showSnackBar(SnackBar(
          content: Text(failure ?? 'Could not save this transaction.'),
          backgroundColor: AppTheme.error));
      return;
    }

    if (code != null) setState(() => _importedCodes = {..._importedCodes, code});

    if (fromSheet) navigator.pop();
    navigator.pop();
    messenger.showSnackBar(SnackBar(
        content: Text(result.type == 'expense'
            ? 'Expense of KES ${result.amount.toStringAsFixed(2)} saved.'
            : 'Income of KES ${result.amount.toStringAsFixed(2)} saved.'),
        backgroundColor: AppTheme.primary));
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message), backgroundColor: Colors.red.shade700));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import M-Pesa'),
        bottom: TabBar(controller: _tabController, tabs: const [
          Tab(text: 'From SMS inbox'), Tab(text: 'Paste message'),
        ]),
      ),
      body: TabBarView(controller: _tabController,
          children: [_buildSmsTab(), _buildPasteTab()]),
    );
  }

  Widget _buildSmsTab() {
    final cs = Theme.of(context).colorScheme;

    if (!_smsPermissionGranted) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.message_outlined, size: 56, color: cs.onSurface.withOpacity(0.4)),
          const SizedBox(height: 20),
          Text('SMS permission needed', style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text('To read your M-Pesa messages automatically, the app needs permission to access your SMS inbox. '
              'Your messages are read locally on your device and never sent anywhere.',
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 24),
          if (_smsError != null) ...[
            Text(_smsError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontSize: 13)),
            const SizedBox(height: 16),
          ],
          ElevatedButton.icon(onPressed: _requestSmsPermission,
              icon: const Icon(Icons.lock_open_outlined), label: const Text('Allow SMS access'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12))),
          const SizedBox(height: 12),
          TextButton(onPressed: () => _tabController.animateTo(1), child: const Text('Use paste tab instead')),
        ]),
      );
    }

    if (_smsLoading) return const Center(child: CircularProgressIndicator());

    if (_smsError != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(_smsError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadSmsMessages, child: const Text('Try again')),
          ])));
    }

    return Column(children: [
      _buildAutoSaveBanner(),
      if (_smsList.isEmpty)
        Expanded(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.inbox_outlined, size: 48, color: cs.onSurface.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text('No M-Pesa messages found in your inbox.',
              style: TextStyle(color: cs.onSurface.withOpacity(0.6))),
          const SizedBox(height: 8),
          Text('Use the Paste tab to test with a sample message.',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton(onPressed: () => _tabController.animateTo(1), child: const Text('Go to Paste tab')),
        ])))
      else
        Expanded(child: RefreshIndicator(onRefresh: _loadSmsMessages,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _smsList.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, index) {
                final sms  = _smsList[index];
                final body = sms.body ?? '';
                final amountMatch = RegExp(r'[Kk]sh([\d,]+\.?\d*)').firstMatch(body);
                final preview = amountMatch != null ? 'KES ${amountMatch.group(1)}' : 'Tap to import';
                final code = MpesaParser.parse(body)?.transactionCode;
                final alreadyImported =
                    code != null && code != 'N/A' && _importedCodes.contains(code);
                return ListTile(
                  leading: CircleAvatar(
                      backgroundColor: alreadyImported
                          ? cs.onSurface.withOpacity(0.10)
                          : AppTheme.primary.withOpacity(0.15),
                      child: Icon(alreadyImported ? Icons.check : Icons.message,
                          color: alreadyImported
                              ? cs.onSurface.withOpacity(0.45)
                              : AppTheme.primary)),
                  title: Text(body.length > 80 ? '${body.substring(0, 80)}...' : body,
                      style: TextStyle(
                          fontSize: 13,
                          color: alreadyImported ? cs.onSurface.withOpacity(0.45) : null),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Row(children: [
                    Text(preview, style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: alreadyImported
                            ? cs.onSurface.withOpacity(0.45)
                            : AppTheme.primary)),
                    if (sms.date != null) ...[
                      Text('  ·  ', style: TextStyle(color: cs.onSurface.withOpacity(0.4))),
                      Text(_formatDate(sms.date!),
                          style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.4))),
                    ],
                    if (alreadyImported) ...[
                      Text('  ·  ', style: TextStyle(color: cs.onSurface.withOpacity(0.4))),
                      Text('Already imported',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                              color: AppTheme.success)),
                    ],
                  ]),
                  // Still tappable when imported: the server refuses the
                  // duplicate and says so, which beats an unexplained dead row.
                  onTap: () => _autoSave
                      ? _handleMessageAutoSave(body, smsDate: sms.date)
                      : _handleMessage(body, smsDate: sms.date),
                );
              },
            ))),
    ]);
  }

  Widget _buildPasteTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _buildAutoSaveBanner(),
        const SizedBox(height: 16),
        Text('Copy your M-Pesa confirmation SMS and paste it below.',
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 6),
        Text('Supported: send money, receive money, pay bill, buy goods, airtime.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
        const SizedBox(height: 16),
        TextField(controller: _pasteController, maxLines: 7,
            decoration: const InputDecoration(
              hintText: 'e.g.\nSB27LJ9O3R Confirmed. Ksh500.00 sent to JOHN KAMAU '
                  '0712345678 on 28/3/25 at 10:34 AM. New M-PESA balance is '
                  'Ksh1,450.00. Transaction cost, Ksh0.00.',
              border: OutlineInputBorder(), alignLabelWithHint: true,
            )),
        const SizedBox(height: 16),
        _MemoryStatusWidget(pasteController: _pasteController),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _saving ? null : () {
            final text = _pasteController.text.trim();
            if (text.isEmpty) { _showError('Please paste an M-Pesa message first.'); return; }
            if (_autoSave) { _handleMessageAutoSave(text); } else { _handleMessage(text); }
            // No smsDate here: pasted text carries no envelope, so the date
            // comes from inside the message body if it has one.
          },
          icon: const Icon(Icons.auto_fix_high_outlined),
          label: _saving
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_autoSave ? 'Import (auto-save)' : 'Parse message'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
        ),
        const SizedBox(height: 24),
        _SampleHintCard(onTap: (sample) => _pasteController.text = sample),
      ]),
    );
  }

  /// Shared auto-save toggle banner used in both tabs.
  Widget _buildAutoSaveBanner() {
    final cs = Theme.of(context).colorScheme;
    final divider = Theme.of(context).dividerColor;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _autoSave ? AppTheme.primary.withOpacity(0.08) : cs.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _autoSave ? AppTheme.primary.withOpacity(0.3) : divider),
      ),
      child: Row(children: [
        Icon(_autoSave ? Icons.flash_on : Icons.flash_off_outlined,
            size: 18, color: _autoSave ? AppTheme.primary : cs.onSurface.withOpacity(0.4)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_autoSave ? 'One-tap import ON' : 'One-tap import OFF',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: _autoSave ? AppTheme.primary : cs.onSurface)),
          Text(_autoSave
              ? 'Known recipients save instantly. New ones still ask.'
              : 'Tap a message to review before saving.',
              style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.6))),
        ])),
        Switch(value: _autoSave, onChanged: _setAutoSave, activeColor: AppTheme.primary),
      ]),
    );
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now(); final diff = now.difference(d);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7)  return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }
}


// ─── Result bottom sheet ──────────────────────────────────────────────────────

class _ResultSheet extends StatefulWidget {
  final MpesaParseResult result;
  final String           initialCategory;
  final bool             fromMemory;

  /// The date this transaction will be filed under. Shown to the user, because
  /// it can come from the message body rather than the SMS envelope, and a
  /// wrong guess should be visible rather than silent.
  final DateTime         transactionDate;

  final Future<void> Function(MpesaParseResult, String, String, String, DateTime,
      {bool fromSheet}) onSave;

  const _ResultSheet({required this.result, required this.initialCategory,
      required this.fromMemory, required this.transactionDate,
      required this.onSave});

  @override
  State<_ResultSheet> createState() => _ResultSheetState();
}

class _ResultSheetState extends State<_ResultSheet> {
  late String _selectedCategory;
  late String _selectedIncomeType;
  late TextEditingController _descController;
  bool _saving = false;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String _sheetDate(DateTime d) {
    final today = DateTime.now();
    final isToday = d.year == today.year && d.month == today.month && d.day == today.day;
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    final stamp = '${d.day} ${_months[d.month - 1]} ${d.year}, $hh:$mm';
    return isToday ? '$stamp (today)' : stamp;
  }

  static const _incomeTypes = ['monthly', 'helb', 'parental', 'gig', 'daily', 'other'];

  @override
  void initState() {
    super.initState();
    _selectedCategory   = widget.initialCategory;
    _selectedIncomeType = widget.result.incomeType;
    _descController     = TextEditingController(text: widget.result.description);
  }

  @override
  void dispose() { _descController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final r         = widget.result;
    final isExpense = r.type == 'expense';
    final cs        = Theme.of(context).colorScheme;
    final divider   = Theme.of(context).dividerColor;

    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Row(children: [
              CircleAvatar(
                backgroundColor: isExpense ? Colors.red.shade50 : Colors.green.shade50,
                child: Icon(isExpense ? Icons.arrow_upward : Icons.arrow_downward,
                    color: isExpense ? Colors.red : AppTheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isExpense ? 'Expense detected' : 'Income detected',
                    style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6))),
                Text('KES ${r.amount.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: divider)),
                child: Text(r.transactionCode,
                    style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.6))),
              ),
            ]),

            const SizedBox(height: 14),

            // ── Date this will be filed under ──────────────────────────────
            // Visible on purpose: for a pasted message the date is read out of
            // the message text, and a misread should be obvious before saving
            // rather than discovered later in the wrong month.
            Row(children: [
              Icon(Icons.event_outlined, size: 16, color: cs.onSurface.withOpacity(0.55)),
              const SizedBox(width: 8),
              Text(_sheetDate(widget.transactionDate),
                  style: TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(0.75))),
            ]),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),

            // ── Description ────────────────────────────────────────────────
            Text('Description', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 6),
            TextField(controller: _descController,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 16),

            // ── Category chips (expenses) ──────────────────────────────────
            if (isExpense) ...[
              Row(children: [
                Text('Category', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(width: 8),
                if (widget.fromMemory)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.primary.withOpacity(0.4))),
                    child: const Text('from memory', style: TextStyle(fontSize: 10,
                        color: AppTheme.primary, fontWeight: FontWeight.w500)),
                  ),
              ]),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: CategorySuggester.allCategories.map((cat) {
                  final selected = cat == _selectedCategory;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? AppTheme.primary : cs.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: selected ? AppTheme.primary : divider),
                      ),
                      child: Text(cat, style: TextStyle(fontSize: 13,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                          color: selected ? Colors.white : cs.onSurface)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // ── Income type chips ──────────────────────────────────────────
            if (!isExpense) ...[
              Text('Income type', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: _incomeTypes.map((type) {
                  final selected = type == _selectedIncomeType;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedIncomeType = type),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? AppTheme.primary : cs.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: selected ? AppTheme.primary : divider),
                      ),
                      child: Text(type.toUpperCase(), style: TextStyle(fontSize: 12,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                          color: selected ? Colors.white : cs.onSurface)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // ── Save button ────────────────────────────────────────────────
            ElevatedButton.icon(
              onPressed: _saving ? null : () async {
                setState(() => _saving = true);
                await widget.onSave(widget.result, _selectedCategory,
                    _descController.text.trim(), _selectedIncomeType,
                    widget.transactionDate, fromSheet: true);
                if (mounted) setState(() => _saving = false);
              },
              icon: _saving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check),
              label: Text(_saving ? 'Saving...' : 'Save transaction'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}


// ─── Memory status widget ─────────────────────────────────────────────────────

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
    if (text.isEmpty) { if (mounted) setState(() => _status = null); return; }
    final result = MpesaParser.parse(text);
    if (result == null) { if (mounted) setState(() => _status = null); return; }
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
      decoration: BoxDecoration(color: _color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8), border: Border.all(color: _color.withOpacity(0.3))),
      child: Row(children: [
        Icon(_color == AppTheme.primary ? Icons.memory : Icons.person_add_outlined, size: 14, color: _color),
        const SizedBox(width: 8),
        Expanded(child: Text(_status!, style: TextStyle(fontSize: 11, color: _color, fontWeight: FontWeight.w500))),
      ]),
    );
  }
}


// ─── Sample hint card ─────────────────────────────────────────────────────────

class _SampleHintCard extends StatelessWidget {
  final void Function(String sample) onTap;
  const _SampleHintCard({required this.onTap});

  static const _samples = {
    'Send money':    'SB27LJ9O3R Confirmed. Ksh500.00 sent to JOHN KAMAU 0712345678 on 28/3/25 at 10:34 AM. New M-PESA balance is Ksh1,450.00. Transaction cost, Ksh0.00.',
    'Receive money': 'SB27LJ9O3R Confirmed. You have received Ksh3,500.00 from MARY WANJIRU 0723456789 on 28/3/25 at 9:12 AM. New M-PESA balance is Ksh4,950.00.',
    'Pay bill':      'SB27LJ9O3R Confirmed. Ksh2,000.00 paid to KENYA POWER Account Number 12345678 on 28/3/25 at 8:00 AM. New M-PESA balance is Ksh800.00. Transaction cost, Ksh0.00.',
    'Buy goods':     'SB27LJ9O3R Confirmed. Ksh250.00 paid to NAIVAS SUPERMARKET. on 28/3/25 at 2:15 PM. New M-PESA balance is Ksh1,200.00. Transaction cost, Ksh0.00.',
    'Airtime':       'SB27LJ9O3R Confirmed. Ksh50.00 airtime bought successfully for 0712345678 on 28/3/25 at 11:05 AM. New M-PESA balance is Ksh750.00.',
    'HELB':          'SB27LJ9O3R Confirmed. You have received Ksh15,000.00 from HELB 0800720765 on 28/3/25 at 7:30 AM. New M-PESA balance is Ksh15,000.00.',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final divider = Theme.of(context).dividerColor;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Try a sample message', style: TextStyle(fontSize: 12,
            fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.6))),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _samples.entries.map((e) => GestureDetector(
              onTap: () => onTap(e.value),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: divider)),
                child: Text(e.key, style: TextStyle(fontSize: 12, color: cs.onSurface)),
              ))).toList(),
        ),
      ]),
    );
  }
}