// lib/ui/helb/helb_planner_screen.dart
//
// HELB Semester Budget Planner — 3 tabs.
// Now uses ApiClient for all HTTP calls (same token handling as every
// other screen) — fixes the 422 Unprocessable Entity error.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:frontend/data/remote/api_client.dart';

const List<String> _kCategories = [
  'Food','Transport','Entertainment','Shopping',
  'Health','Education','Utilities','Rent','Other',
];
const List<String> _kNeeds = ['Food','Transport','Health','Education','Utilities','Rent'];
const List<String> _kWants = ['Entertainment','Shopping','Other'];
const String _kApiBase = 'http://10.0.2.2:5000/api';

// ── Lightweight in-memory plan model ─────────────────────────────────────────
class _PlanData {
  final int id;
  final String semesterName;
  final double helbAmount;
  final DateTime startDate;
  final DateTime endDate;
  final Map<String, double> allocations;

  _PlanData({required this.id,required this.semesterName,required this.helbAmount,
    required this.startDate,required this.endDate,required this.allocations});

  factory _PlanData.fromJson(Map<String,dynamic> j) => _PlanData(
    id:           (j['id'] as num).toInt(),
    semesterName: j['semester_name'] as String,
    helbAmount:   (j['helb_amount'] as num).toDouble(),
    startDate:    DateTime.parse(j['start_date'] as String),
    endDate:      DateTime.parse(j['end_date'] as String),
    allocations:  (j['allocations'] as Map<String,dynamic>? ?? {})
        .map((k,v) => MapEntry(k,(v as num).toDouble())),
  );

  int get totalDays => endDate.difference(startDate).inDays.clamp(1,9999);
  int get daysElapsed {
    final now = DateTime.now();
    if (now.isBefore(startDate)) return 0;
    if (now.isAfter(endDate)) return totalDays;
    return now.difference(startDate).inDays.clamp(0,totalDays);
  }
  int get daysRemaining => (totalDays - daysElapsed).clamp(0,totalDays);
  double get progressFraction => daysElapsed / totalDays;
  double get expectedSpentByNow => helbAmount * progressFraction;
  double get allocationsTotal => allocations.values.fold(0.0,(a,b) => a+b);
}

// ─────────────────────────────────────────────────────────────────────────────

class HelbPlannerScreen extends StatefulWidget {
  const HelbPlannerScreen({super.key});
  @override State<HelbPlannerScreen> createState() => _HelbPlannerScreenState();
}

class _HelbPlannerScreenState extends State<HelbPlannerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  _PlanData? _plan;
  bool _loading = true;
  bool _saving  = false;
  Map<String,double> _categorySpent = {};
  double _totalSpent = 0.0;
  bool _expensesLoading = false;

  final _formKey = GlobalKey<FormState>();
  final _semesterNameCtrl = TextEditingController();
  final _helbAmountCtrl   = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  late final Map<String,TextEditingController> _allocCtrl;
  final _fmt     = NumberFormat('#,##0.00','en_US');
  final _dateFmt = DateFormat('dd MMM yyyy');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length:3,vsync:this);
    _allocCtrl = { for (final cat in _kCategories) cat: TextEditingController() };
    _fetchPlan();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _semesterNameCtrl.dispose();
    _helbAmountCtrl.dispose();
    for (final c in _allocCtrl.values) c.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Data — uses ApiClient (same token handling as all other screens)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _fetchPlan() async {
    setState(() => _loading = true);
    try {
      final body = await ApiClient.getHelbPlan();
      final pj   = body['plan'];
      if (!mounted) return;
      setState(() {
        _plan    = pj != null ? _PlanData.fromJson(pj as Map<String,dynamic>) : null;
        _loading = false;
        if (_plan != null) { _populateForm(_plan!); _tabController.animateTo(1); }
      });
      if (_plan != null) _fetchSemesterExpenses(_plan!);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _populateForm(_PlanData p) {
    _semesterNameCtrl.text = p.semesterName;
    _helbAmountCtrl.text   = p.helbAmount.toStringAsFixed(0);
    _startDate = p.startDate; _endDate = p.endDate;
    for (final cat in _kCategories) {
      final a = p.allocations[cat] ?? 0.0;
      _allocCtrl[cat]!.text = a > 0 ? a.toStringAsFixed(0) : '';
    }
  }

  Future<void> _fetchSemesterExpenses(_PlanData plan) async {
    if (!mounted) return;
    setState(() => _expensesLoading = true);
    final Map<String,double> totals = {};
    for (final ym in _monthsInRange(plan.startDate, plan.endDate)) {
      try {
        final body     = await ApiClient.getExpenses(month: ym['month']!, year: ym['year']!);
        final expenses = body['expenses'] as List<dynamic>;
        for (final e in expenses) {
          final d = DateTime.parse(e['date_added'] as String);
          if (!d.isBefore(plan.startDate) && !d.isAfter(plan.endDate) && e['expense_type'] != 'one-time') {
            final cat = e['category'] as String;
            totals[cat] = (totals[cat] ?? 0.0) + (e['amount'] as num).toDouble();
          }
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _categorySpent   = totals;
      _totalSpent      = totals.values.fold(0.0,(a,b)=>a+b);
      _expensesLoading = false;
    });
  }

  List<Map<String,int>> _monthsInRange(DateTime s, DateTime e) {
    final months = <Map<String,int>>[]; var y=s.year,m=s.month;
    while (DateTime(y,m).compareTo(DateTime(e.year,e.month))<=0) {
      months.add({'year':y,'month':m}); m++; if(m>12){m=1;y++;}
    }
    return months;
  }

  Future<void> _savePlan() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate==null||_endDate==null) { _showSnack('Please set both the start and end dates'); return; }
    if (_endDate!.isBefore(_startDate!)) { _showSnack('End date must be after start date'); return; }
    final allocs = <String,double>{};
    for (final c in _kCategories) { final v=double.tryParse(_allocCtrl[c]!.text); if(v!=null&&v>0) allocs[c]=v; }
    setState(() => _saving = true);
    try {
      final body = await ApiClient.saveHelbPlan(
        semesterName: _semesterNameCtrl.text.trim(),
        helbAmount:   double.parse(_helbAmountCtrl.text),
        startDate:    _startDate!.toIso8601String().split('T').first,
        endDate:      _endDate!.toIso8601String().split('T').first,
        allocations:  allocs,
      );
      if (!mounted) return;
      final plan = _PlanData.fromJson(body['plan'] as Map<String,dynamic>);
      setState(() { _plan=plan; _saving=false; });
      _showSnack('Semester plan saved!', isSuccess: true);
      _fetchSemesterExpenses(plan);
      _tabController.animateTo(1);
    } on ApiException catch (e) {
      if (mounted) { setState(()=>_saving=false); _showSnack(e.message); }
    } catch (_) {
      if (mounted) { setState(()=>_saving=false); _showSnack('Could not save plan. Check your connection.'); }
    }
  }

  Future<void> _deletePlan() async {
    final ok = await showDialog<bool>(context:context,builder:(_)=>AlertDialog(
      title:const Text('Delete Plan'),
      content:const Text('Delete your semester budget plan? This cannot be undone.'),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),
        TextButton(onPressed:()=>Navigator.pop(context,true),style:TextButton.styleFrom(foregroundColor:Colors.red),child:const Text('Delete')),
      ],
    ));
    if (ok!=true) return;
    try {
      await ApiClient.deleteHelbPlan();
      if (!mounted) return;
      setState((){
        _plan=null; _categorySpent={}; _totalSpent=0;
        _semesterNameCtrl.clear(); _helbAmountCtrl.clear();
        _startDate=null; _endDate=null;
        for (final c in _allocCtrl.values) c.clear();
      });
      _tabController.animateTo(0);
      _showSnack('Plan deleted.');
    } on ApiException catch (e) {
      if (mounted) _showSnack(e.message);
    } catch (_) {
      if (mounted) _showSnack('Could not delete plan. Check your connection.');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Setup helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart?(_startDate??DateTime.now()):(_endDate??DateTime.now().add(const Duration(days:120)));
    final first   = isStart?DateTime(2024):(_startDate??DateTime(2024));
    final picked  = await showDatePicker(context:context,initialDate:initial,firstDate:first,lastDate:DateTime(2030));
    if (picked!=null && mounted) setState(() {
      if (isStart) { _startDate=picked; if(_endDate!=null&&_endDate!.isBefore(picked)) _endDate=null; }
      else _endDate = picked;
    });
  }

  void _applyEqualSplit() {
    final a = double.tryParse(_helbAmountCtrl.text);
    if (a==null||a<=0) { _showSnack('Enter your HELB amount first'); return; }
    final p = (a/_kCategories.length).floorToDouble();
    for (final c in _kCategories) _allocCtrl[c]!.text = p.toStringAsFixed(0);
    setState((){});
  }

  void _apply503020() {
    final a = double.tryParse(_helbAmountCtrl.text);
    if (a==null||a<=0) { _showSnack('Enter your HELB amount first'); return; }
    final needs=a*0.50; final wants=a*0.30;
    for (final c in _kNeeds) _allocCtrl[c]!.text = (needs/_kNeeds.length).floorToDouble().toStringAsFixed(0);
    for (final c in _kWants) _allocCtrl[c]!.text = (wants/_kWants.length).floorToDouble().toStringAsFixed(0);
    setState((){});
  }

  void _showSnack(String msg,{bool isSuccess=false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:Text(msg), backgroundColor:isSuccess?Colors.green.shade700:null));
  }

  double _allocTotal() => _kCategories.fold(0.0,(a,c)=>a+(double.tryParse(_allocCtrl[c]!.text)??0.0));

  int? _moneyLastsDays(_PlanData plan) {
    if (_totalSpent<=0||plan.daysElapsed<=0) return null;
    final r=(plan.helbAmount-_totalSpent).clamp(0.0,double.infinity);
    return (r/(_totalSpent/plan.daysElapsed)).floor();
  }

  String _statusLabel(double spent,_PlanData p) {
    if (p.daysElapsed==0) return 'Not Started';
    if (spent<=p.expectedSpentByNow*0.85) return 'Ahead';
    if (spent<=p.expectedSpentByNow*1.05) return 'On Track';
    if (spent<=p.expectedSpentByNow*1.30) return 'Behind';
    return 'Critical';
  }
  Color _statusColor(String s){ switch(s){ case 'Ahead':return Colors.green.shade600; case 'On Track':return Colors.teal.shade600; case 'Behind':return Colors.orange.shade700; case 'Critical':return Colors.red.shade600; default:return Colors.blue.shade600; } }
  IconData _statusIcon(String s){ switch(s){ case 'Ahead':return Icons.trending_up; case 'On Track':return Icons.check_circle_outline; case 'Behind':return Icons.warning_amber_outlined; case 'Critical':return Icons.crisis_alert_outlined; default:return Icons.hourglass_empty_outlined; } }
  IconData _catIcon(String c){ switch(c){ case 'Food':return Icons.restaurant_outlined; case 'Transport':return Icons.directions_bus_outlined; case 'Entertainment':return Icons.movie_outlined; case 'Shopping':return Icons.shopping_bag_outlined; case 'Health':return Icons.health_and_safety_outlined; case 'Education':return Icons.menu_book_outlined; case 'Utilities':return Icons.power_outlined; case 'Rent':return Icons.home_outlined; default:return Icons.category_outlined; } }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body:Center(child:CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        title: const Text('HELB Semester Planner'),
        bottom: TabBar(controller:_tabController,tabs:const[
          Tab(icon:Icon(Icons.settings_outlined),text:'Setup'),
          Tab(icon:Icon(Icons.dashboard_outlined),text:'Overview'),
          Tab(icon:Icon(Icons.bar_chart_outlined),text:'Breakdown'),
        ]),
      ),
      body: TabBarView(controller:_tabController,children:[_buildSetupTab(),_buildOverviewTab(),_buildBreakdownTab()]),
    );
  }

  // ── TAB 1 SETUP ──────────────────────────────────────────────────────────

  Widget _buildSetupTab() {
    final h=double.tryParse(_helbAmountCtrl.text)??0.0;
    final ta=_allocTotal(); final ua=h-ta; final over=ua<-0.01;
    return Form(key:_formKey,child:ListView(padding:const EdgeInsets.all(16),children:[
      _secHeader('Semester Details'), const SizedBox(height:10),
      TextFormField(controller:_semesterNameCtrl,textCapitalization:TextCapitalization.words,
        decoration:const InputDecoration(labelText:'Semester Name',hintText:'e.g. Semester 1 2025',prefixIcon:Icon(Icons.school_outlined),border:OutlineInputBorder()),
        validator:(v)=>(v==null||v.trim().isEmpty)?'Required':null),
      const SizedBox(height:12),
      TextFormField(controller:_helbAmountCtrl,
        decoration:const InputDecoration(labelText:'HELB / Lump-Sum Amount',prefixText:'KES ',prefixIcon:Icon(Icons.account_balance_wallet_outlined),border:OutlineInputBorder()),
        keyboardType:TextInputType.number,inputFormatters:[FilteringTextInputFormatter.digitsOnly],
        onChanged:(_)=>setState((){}),
        validator:(v){ final n=double.tryParse(v??''); return(n==null||n<=0)?'Enter a valid amount':null; }),
      const SizedBox(height:12),
      Row(children:[
        Expanded(child:_dateTile(label:'Start Date',date:_startDate,isStart:true)),
        const SizedBox(width:12),
        Expanded(child:_dateTile(label:'End Date',date:_endDate,isStart:false)),
      ]),
      if (_startDate!=null&&_endDate!=null&&!_endDate!.isBefore(_startDate!))
        Padding(padding:const EdgeInsets.only(top:6),child:Text(
          '${_endDate!.difference(_startDate!).inDays} days  (${(_endDate!.difference(_startDate!).inDays/30).toStringAsFixed(1)} months)',
          style:Theme.of(context).textTheme.bodySmall?.copyWith(color:Colors.grey.shade600))),
      const SizedBox(height:24),
      _secHeader('Budget Allocations'), const SizedBox(height:4),
      Text('Divide your HELB across categories. Leave a category empty to skip it. Any unallocated amount becomes your implied savings.',
        style:Theme.of(context).textTheme.bodySmall?.copyWith(color:Colors.grey.shade600)),
      const SizedBox(height:10),
      Row(children:[
        Expanded(child:OutlinedButton.icon(onPressed:_applyEqualSplit,icon:const Icon(Icons.balance,size:16),label:const Text('Equal Split'))),
        const SizedBox(width:8),
        Expanded(child:OutlinedButton.icon(onPressed:_apply503020,icon:const Icon(Icons.pie_chart_outline,size:16),label:const Text('50/30/20'))),
      ]),
      Padding(padding:const EdgeInsets.only(top:4,bottom:12),
        child:Text('50% Needs · 30% Wants · 20% implied savings',style:Theme.of(context).textTheme.bodySmall?.copyWith(color:Colors.grey,fontStyle:FontStyle.italic))),
      ..._kCategories.map((cat)=>Padding(padding:const EdgeInsets.only(bottom:10),child:TextFormField(
        controller:_allocCtrl[cat],onChanged:(_)=>setState((){}),
        decoration:InputDecoration(labelText:cat,prefixText:'KES ',border:const OutlineInputBorder(),prefixIcon:Icon(_catIcon(cat),size:20)),
        keyboardType:TextInputType.number,inputFormatters:[FilteringTextInputFormatter.digitsOnly]))),
      const SizedBox(height:4),
      _allocBanner(h:h,ta:ta,ua:ua,over:over),
      const SizedBox(height:20),
      ElevatedButton.icon(
        onPressed:_saving?null:_savePlan,
        icon:_saving?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):const Icon(Icons.save_outlined),
        label:Text(_plan==null?'Save Plan':'Update Plan'),
        style:ElevatedButton.styleFrom(minimumSize:const Size.fromHeight(48))),
      if (_plan!=null)...[
        const SizedBox(height:8),
        OutlinedButton.icon(onPressed:_deletePlan,icon:const Icon(Icons.delete_outline,color:Colors.red),label:const Text('Delete Plan',style:TextStyle(color:Colors.red)),
          style:OutlinedButton.styleFrom(minimumSize:const Size.fromHeight(48),side:const BorderSide(color:Colors.red))),
      ],
      const SizedBox(height:32),
    ]));
  }

  Widget _dateTile({required String label,required DateTime? date,required bool isStart}) =>
    InkWell(onTap:()=>_pickDate(isStart:isStart),borderRadius:BorderRadius.circular(8),
      child:Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:14),
        decoration:BoxDecoration(border:Border.all(color:Colors.grey.shade400),borderRadius:BorderRadius.circular(8)),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(label,style:const TextStyle(fontSize:11,color:Colors.grey)),const SizedBox(height:4),
          Row(children:[const Icon(Icons.calendar_today_outlined,size:16),const SizedBox(width:6),
            Text(date!=null?_dateFmt.format(date):'Tap to set',
              style:TextStyle(color:date!=null?null:Colors.grey,fontWeight:date!=null?FontWeight.w500:FontWeight.normal,fontSize:13))]),
        ])));

  Widget _allocBanner({required double h,required double ta,required double ua,required bool over}) {
    final bc = over?Colors.red:ua<0.01?Colors.green:Colors.blue.shade400;
    final bg = over?Colors.red.shade50:ua<0.01?Colors.green.shade50:Colors.blue.shade50;
    return Container(padding:const EdgeInsets.all(12),
      decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(8),border:Border.all(color:bc)),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
          const Text('Total Allocated',style:TextStyle(fontWeight:FontWeight.w600)),
          Text('KES ${_fmt.format(ta)} / ${_fmt.format(h)}',style:TextStyle(fontWeight:FontWeight.bold,color:over?Colors.red.shade700:Colors.blue.shade700)),
        ]),
        const SizedBox(height:4),
        if(over) Text('Over-allocated by KES ${_fmt.format(ua.abs())} — reduce some categories.',style:TextStyle(fontSize:12,color:Colors.red.shade700))
        else if(ua>0.01) Text('KES ${_fmt.format(ua)} unallocated — this becomes your implied savings.',style:TextStyle(fontSize:12,color:Colors.blue.shade700))
        else Text('Fully allocated. Every shilling has a job.',style:TextStyle(fontSize:12,color:Colors.green.shade700)),
      ]));
  }

  // ── TAB 2 OVERVIEW ───────────────────────────────────────────────────────

  Widget _buildOverviewTab() {
    if (_plan==null) return _noData(icon:Icons.calendar_month_outlined,msg:'No semester plan yet.\nGo to Setup to create one.');
    final p=_plan!;
    final rem=(p.helbAmount-_totalSpent).clamp(0.0,double.infinity);
    final pct=p.helbAmount>0?(rem/p.helbAmount*100).clamp(0.0,100.0):0.0;
    final daily=p.daysRemaining>0?rem/p.daysRemaining:0.0;
    final status=_statusLabel(_totalSpent,p); final sc=_statusColor(status);
    final dp=p.progressFraction.clamp(0.0,1.0);
    final impl=(p.helbAmount-p.allocationsTotal).clamp(0.0,double.infinity);
    return RefreshIndicator(onRefresh:()=>_fetchSemesterExpenses(p),child:ListView(padding:const EdgeInsets.all(16),children:[
      Text(p.semesterName,style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),
      const SizedBox(height:2),
      Text('${_dateFmt.format(p.startDate)} — ${_dateFmt.format(p.endDate)}',style:Theme.of(context).textTheme.bodySmall?.copyWith(color:Colors.grey)),
      const SizedBox(height:14),
      Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
          Text('Day ${p.daysElapsed} of ${p.totalDays}',style:const TextStyle(fontWeight:FontWeight.w600)),
          Text('${p.daysRemaining} days left',style:TextStyle(color:p.daysRemaining<14?Colors.orange.shade700:Colors.grey,fontWeight:FontWeight.w500)),
        ]),
        const SizedBox(height:10),
        ClipRRect(borderRadius:BorderRadius.circular(4),child:LinearProgressIndicator(value:dp,minHeight:10,
          backgroundColor:Colors.grey.shade200,valueColor:AlwaysStoppedAnimation(dp>0.9?Colors.orange.shade600:Colors.blue.shade500))),
        const SizedBox(height:4),
        Text('${(dp*100).toStringAsFixed(0)}% of semester elapsed',style:Theme.of(context).textTheme.bodySmall?.copyWith(color:Colors.grey)),
      ]))),
      const SizedBox(height:8),
      _buildPaceCard(p), const SizedBox(height:8),
      Center(child:Chip(
        avatar:Icon(_statusIcon(status),color:sc,size:18),
        label:Text(status,style:TextStyle(color:sc,fontWeight:FontWeight.bold)),
        backgroundColor:sc.withOpacity(0.1),side:BorderSide(color:sc.withOpacity(0.3)))),
      const SizedBox(height:10),
      Card(color:pct>30?Colors.green.shade50:pct>10?Colors.orange.shade50:Colors.red.shade50,elevation:0,
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12),
          side:BorderSide(color:pct>30?Colors.green.shade200:pct>10?Colors.orange.shade200:Colors.red.shade200)),
        child:Padding(padding:const EdgeInsets.symmetric(vertical:20,horizontal:16),child:Column(children:[
          Text('Remaining Balance',style:Theme.of(context).textTheme.titleSmall?.copyWith(color:Colors.grey.shade600)),
          const SizedBox(height:6),
          _expensesLoading?const SizedBox(height:36,child:Center(child:CircularProgressIndicator(strokeWidth:2)))
            :Text('KES ${_fmt.format(rem)}',style:Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight:FontWeight.bold,
                color:pct>30?Colors.green.shade700:pct>10?Colors.orange.shade700:Colors.red.shade700)),
          const SizedBox(height:4),
          Text('${pct.toStringAsFixed(1)}% of KES ${_fmt.format(p.helbAmount)}',style:Theme.of(context).textTheme.bodySmall?.copyWith(color:Colors.grey.shade600)),
        ]))),
      const SizedBox(height:10),
      Row(children:[
        Expanded(child:_stat(label:'Daily Safe-to-Spend',value:'KES ${_fmt.format(daily)}',icon:Icons.today_outlined,color:Colors.blue.shade600)),
        const SizedBox(width:8),
        Expanded(child:_stat(label:'Total Spent',value:'KES ${_fmt.format(_totalSpent)}',icon:Icons.receipt_long_outlined,color:Colors.orange.shade700,loading:_expensesLoading)),
      ]),
      const SizedBox(height:8),
      Row(children:[
        Expanded(child:_stat(label:'Expected by Today',value:'KES ${_fmt.format(p.expectedSpentByNow)}',icon:Icons.schedule_outlined,color:Colors.purple.shade500)),
        const SizedBox(width:8),
        Expanded(child:_stat(
          label:_totalSpent<=p.expectedSpentByNow?'Saved vs Pace':'Over Pace By',
          value:_totalSpent<=p.expectedSpentByNow?'KES ${_fmt.format(p.expectedSpentByNow-_totalSpent)}':'KES ${_fmt.format(_totalSpent-p.expectedSpentByNow)}',
          icon:Icons.compare_arrows_outlined,
          color:_totalSpent<=p.expectedSpentByNow?Colors.green.shade600:Colors.red.shade600,loading:_expensesLoading)),
      ]),
      if (impl>0.01)...[
        const SizedBox(height:10),
        Container(padding:const EdgeInsets.symmetric(horizontal:14,vertical:12),
          decoration:BoxDecoration(color:Colors.green.shade50,borderRadius:BorderRadius.circular(10),border:Border.all(color:Colors.green.shade200)),
          child:Row(children:[
            Icon(Icons.savings_outlined,size:20,color:Colors.green.shade700),const SizedBox(width:10),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              const Text('Implied Savings (Unallocated)',style:TextStyle(fontSize:13,fontWeight:FontWeight.w600)),
              const SizedBox(height:2),
              Text('${(impl/p.helbAmount*100).toStringAsFixed(1)}% of your HELB has no category assigned',
                style:TextStyle(fontSize:11,color:Colors.grey.shade600)),
            ])),
            const SizedBox(width:8),
            Text('KES ${_fmt.format(impl)}',style:TextStyle(fontWeight:FontWeight.bold,fontSize:13,color:Colors.green.shade700)),
          ])),
      ],
      const SizedBox(height:16),
      OutlinedButton.icon(onPressed:()=>_tabController.animateTo(0),icon:const Icon(Icons.edit_outlined),label:const Text('Edit Plan'),
        style:OutlinedButton.styleFrom(minimumSize:const Size.fromHeight(44))),
      const SizedBox(height:24),
    ]));
  }

  Widget _buildPaceCard(_PlanData p) {
    final md = _moneyLastsDays(p);
    if (_expensesLoading) return Card(child:Padding(padding:const EdgeInsets.all(14),child:Row(children:[
      const Icon(Icons.hourglass_empty_outlined,size:20,color:Colors.grey),const SizedBox(width:10),
      Text('Calculating pace...',style:TextStyle(color:Colors.grey.shade600))])));
    if (md==null) return Card(child:Padding(padding:const EdgeInsets.all(14),child:Row(children:[
      Icon(Icons.info_outline,size:20,color:Colors.grey.shade400),const SizedBox(width:10),
      Expanded(child:Text('No spending recorded yet — pace projection will appear once you log expenses.',style:TextStyle(color:Colors.grey.shade500,fontSize:13)))])));
    final diff = md - p.daysRemaining;
    Color cc; Color bc; IconData ic; String hl; String sl;
    if (md<=0){cc=Colors.red.shade50;bc=Colors.red.shade300;ic=Icons.crisis_alert_outlined;hl='HELB already depleted at this pace';sl='Reduce spending immediately.';}
    else if (diff<-14){cc=Colors.red.shade50;bc=Colors.red.shade300;ic=Icons.crisis_alert_outlined;hl='HELB runs out in ~$md days';sl='${diff.abs()} days before semester ends — critical overspend.';}
    else if (diff<0){cc=Colors.orange.shade50;bc=Colors.orange.shade300;ic=Icons.warning_amber_outlined;hl='HELB runs out in ~$md days';sl='${diff.abs()} days short of semester end — reduce spending.';}
    else if (diff<=14){cc=Colors.teal.shade50;bc=Colors.teal.shade300;ic=Icons.check_circle_outline;hl='HELB lasts ~$md more days';sl='Outlasts semester by $diff days — stay disciplined.';}
    else{cc=Colors.green.shade50;bc=Colors.green.shade300;ic=Icons.savings_outlined;hl='HELB lasts ~$md more days';sl='Outlasts semester by $diff days ✅ — excellent pace.';}
    final dr = p.daysElapsed>0?_totalSpent/p.daysElapsed:0.0;
    return Card(elevation:0,color:cc,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12),side:BorderSide(color:bc)),
      child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[Icon(Icons.speed_outlined,size:16,color:bc),const SizedBox(width:6),
          Text('Spending Pace Projection',style:TextStyle(fontSize:12,fontWeight:FontWeight.w600,color:Colors.grey.shade600))]),
        const SizedBox(height:10),
        Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Icon(ic,size:22,color:bc),const SizedBox(width:10),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(hl,style:TextStyle(fontWeight:FontWeight.bold,fontSize:14,color:bc)),
            const SizedBox(height:3),Text(sl,style:TextStyle(fontSize:12,color:Colors.grey.shade700)),
          ])),
        ]),
        const SizedBox(height:10),Divider(height:1,color:bc.withOpacity(0.4)),const SizedBox(height:8),
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
          Text('Current daily spend rate',style:TextStyle(fontSize:12,color:Colors.grey.shade600)),
          Text('KES ${_fmt.format(dr)}/day',style:const TextStyle(fontSize:12,fontWeight:FontWeight.w600)),
        ]),
      ])));
  }

  Widget _stat({required String label,required String value,required IconData icon,required Color color,bool loading=false}) =>
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Icon(icon,size:14,color:color),const SizedBox(width:5),
        Expanded(child:Text(label,style:Theme.of(context).textTheme.bodySmall?.copyWith(color:Colors.grey.shade600),maxLines:1,overflow:TextOverflow.ellipsis))]),
      const SizedBox(height:6),
      loading?const SizedBox(height:16,width:16,child:CircularProgressIndicator(strokeWidth:2))
        :Text(value,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:13),maxLines:2,overflow:TextOverflow.ellipsis),
    ])));

  // ── TAB 3 BREAKDOWN ──────────────────────────────────────────────────────

  Widget _buildBreakdownTab() {
    if (_plan==null) return _noData(icon:Icons.bar_chart_outlined,msg:'No semester plan yet.\nGo to Setup to create one.');
    final p=_plan!;
    final alloc=_kCategories.where((c)=>(p.allocations[c]??0)>0).toList();
    final unalloc=_kCategories.where((c)=>(p.allocations[c]??0)<=0).toList();
    return RefreshIndicator(onRefresh:()=>_fetchSemesterExpenses(p),
      child:_expensesLoading?const Center(child:CircularProgressIndicator())
        :ListView(padding:const EdgeInsets.all(16),children:[
          Text('${p.semesterName} — Category Breakdown',style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.bold)),
          const SizedBox(height:12),
          if (alloc.isEmpty) Card(child:Padding(padding:const EdgeInsets.all(24),child:Column(children:[
            Icon(Icons.pie_chart_outline,size:48,color:Colors.grey.shade300),const SizedBox(height:12),
            Text('No category allocations set.\nGo to Setup to allocate your budget.',textAlign:TextAlign.center,style:TextStyle(color:Colors.grey.shade500))])))
          else...[
            ...alloc.map((c)=>_catBar(c,p)),
            if (unalloc.isNotEmpty)...[
              const SizedBox(height:16),_secHeader('Unallocated Categories'),const SizedBox(height:4),
              Text('Spending in these categories is not tracked against a limit.',style:Theme.of(context).textTheme.bodySmall?.copyWith(color:Colors.grey)),
              const SizedBox(height:8),
              Wrap(spacing:8,runSpacing:4,children:unalloc.map((c){
                final s=_categorySpent[c]??0;
                return Chip(avatar:Icon(_catIcon(c),size:14),label:Text(s>0?'$c (KES ${_fmt.format(s)})':c),
                  backgroundColor:s>0?Colors.orange.shade50:null);
              }).toList()),
            ],
          ],
          const SizedBox(height:32),
        ]));
  }

  Widget _catBar(String cat, _PlanData p) {
    final alloc=p.allocations[cat]??0.0; final spent=_categorySpent[cat]??0.0;
    final prog=alloc>0?(spent/alloc).clamp(0.0,1.5):0.0;
    final over=spent>alloc; final near=!over&&prog>0.8;
    final Color bc; final String sl;
    if(over){bc=Colors.red.shade600;sl='Over Budget';}
    else if(near){bc=Colors.orange.shade600;sl='Near Limit';}
    else{bc=Colors.green.shade600;sl='On Track';}
    final rem=(alloc-spent).clamp(0.0,double.infinity);
    final dn=p.daysRemaining>0&&rem>0?rem/p.daysRemaining:0.0;
    return Card(margin:const EdgeInsets.only(bottom:10),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[
        Icon(_catIcon(cat),size:20,color:bc),const SizedBox(width:8),
        Expanded(child:Text(cat,style:const TextStyle(fontWeight:FontWeight.w600,fontSize:15))),
        Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:2),
          decoration:BoxDecoration(color:bc.withOpacity(0.1),borderRadius:BorderRadius.circular(12),border:Border.all(color:bc.withOpacity(0.4))),
          child:Text(sl,style:TextStyle(fontSize:11,color:bc,fontWeight:FontWeight.bold))),
      ]),
      const SizedBox(height:10),
      ClipRRect(borderRadius:BorderRadius.circular(4),child:LinearProgressIndicator(value:prog.clamp(0.0,1.0),minHeight:8,
        backgroundColor:Colors.grey.shade200,valueColor:AlwaysStoppedAnimation(bc))),
      const SizedBox(height:6),
      Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
        Text('KES ${_fmt.format(spent)} of ${_fmt.format(alloc)}',style:Theme.of(context).textTheme.bodySmall),
        Text('${(prog*100).clamp(0,150).toStringAsFixed(0)}%',style:TextStyle(fontSize:12,fontWeight:FontWeight.bold,color:bc)),
      ]),
      if(!over&&p.daysRemaining>0&&rem>0) Padding(padding:const EdgeInsets.only(top:4),
        child:Text('Budget: KES ${_fmt.format(dn)}/day for ${p.daysRemaining} days',style:Theme.of(context).textTheme.bodySmall?.copyWith(color:Colors.grey.shade600))),
      if(over) Padding(padding:const EdgeInsets.only(top:4),
        child:Text('Overspent by KES ${_fmt.format(spent-alloc)}',style:Theme.of(context).textTheme.bodySmall?.copyWith(color:Colors.red.shade700))),
    ])));
  }

  Widget _noData({required IconData icon,required String msg}) => Center(child:Padding(padding:const EdgeInsets.all(32),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
    Icon(icon,size:72,color:Colors.grey.shade200),const SizedBox(height:16),
    Text(msg,textAlign:TextAlign.center,style:TextStyle(color:Colors.grey.shade500,fontSize:15)),
    const SizedBox(height:20),
    OutlinedButton.icon(onPressed:()=>_tabController.animateTo(0),icon:const Icon(Icons.add),label:const Text('Set Up Plan')),
  ])));

  Widget _secHeader(String t) => Text(t,style:Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight:FontWeight.bold,color:Theme.of(context).colorScheme.primary));
}