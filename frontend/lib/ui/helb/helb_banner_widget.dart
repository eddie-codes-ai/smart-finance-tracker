// lib/ui/helb/helb_banner_widget.dart
// Now uses ApiClient for the plan fetch — same token handling as every
// other screen — fixes the 422 Unprocessable Entity error.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:frontend/core/routes.dart';
import 'package:frontend/data/remote/api_client.dart';

class _BannerPlan {
  final String semesterName;
  final double helbAmount;
  final DateTime startDate;
  final DateTime endDate;

  _BannerPlan({required this.semesterName,required this.helbAmount,
    required this.startDate,required this.endDate});

  factory _BannerPlan.fromJson(Map<String,dynamic> j) => _BannerPlan(
    semesterName: j['semester_name'] as String,
    helbAmount:   (j['helb_amount'] as num).toDouble(),
    startDate:    DateTime.parse(j['start_date'] as String),
    endDate:      DateTime.parse(j['end_date'] as String),
  );

  int get totalDays => endDate.difference(startDate).inDays.clamp(1,9999);
  int get daysElapsed {
    final now = DateTime.now();
    if (now.isBefore(startDate)) return 0;
    if (now.isAfter(endDate)) return totalDays;
    return now.difference(startDate).inDays.clamp(0,totalDays);
  }
  int get daysRemaining => (totalDays-daysElapsed).clamp(0,totalDays);
  double get progressFraction => daysElapsed/totalDays;
}

class HelbBannerWidget extends StatefulWidget {
  const HelbBannerWidget({super.key});
  @override State<HelbBannerWidget> createState() => _HelbBannerWidgetState();
}

class _HelbBannerWidgetState extends State<HelbBannerWidget> {
  _BannerPlan? _plan;
  bool _checked = false;
  final _fmt = NumberFormat('#,##0.00','en_US');

  @override
  void initState() { super.initState(); _loadPlan(); }

  Future<void> _loadPlan() async {
    try {
      final body = await ApiClient.getHelbPlan();
      final pj   = body['plan'];
      if (!mounted) return;
      setState(() {
        _plan    = pj != null ? _BannerPlan.fromJson(pj as Map<String,dynamic>) : null;
        _checked = true;
      });
    } catch (_) {
      if (mounted) setState(() => _checked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) return const SizedBox.shrink();

    // ── No plan — prompt card ─────────────────────────────────────────────
    if (_plan==null) {
      return GestureDetector(
        onTap:()=>Navigator.pushNamed(context,AppRoutes.helbPlanner),
        child:Card(
          margin:const EdgeInsets.symmetric(horizontal:16,vertical:6),elevation:1,
          shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),
          child:Padding(padding:const EdgeInsets.all(14),child:Row(children:[
            Container(width:40,height:40,decoration:BoxDecoration(color:Colors.blue.shade50,borderRadius:BorderRadius.circular(10)),
              child:Icon(Icons.school_outlined,size:20,color:Colors.blue.shade600)),
            const SizedBox(width:12),
            const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('HELB Semester Planner',style:TextStyle(fontWeight:FontWeight.w700,fontSize:14)),
              SizedBox(height:2),
              Text('Tap to ration your HELB across the semester',style:TextStyle(fontSize:12,color:Colors.grey)),
            ])),
            const Icon(Icons.chevron_right,size:18,color:Colors.grey),
          ]))));
    }

    // ── Plan exists — progress card ───────────────────────────────────────
    final p  = _plan!;
    final dp = p.progressFraction.clamp(0.0,1.0);
    final pc = dp>0.9?Colors.orange.shade600:Colors.blue.shade500;

    return GestureDetector(
      onTap:()=>Navigator.pushNamed(context,AppRoutes.helbPlanner).then((_){
        setState(()=>_checked=false);
        _loadPlan();
      }),
      child:Card(
        margin:const EdgeInsets.symmetric(horizontal:16,vertical:6),elevation:2,
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),
        child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[
            Container(width:36,height:36,decoration:BoxDecoration(color:Colors.blue.shade50,borderRadius:BorderRadius.circular(8)),
              child:Icon(Icons.school_outlined,size:18,color:Colors.blue.shade600)),
            const SizedBox(width:10),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(p.semesterName,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:15)),
              Text('HELB Semester Planner',style:TextStyle(fontSize:11,color:Colors.grey.shade500)),
            ])),
            Text('${p.daysRemaining} days left',
              style:TextStyle(fontSize:12,color:p.daysRemaining<14?Colors.orange.shade700:Colors.grey.shade600,fontWeight:FontWeight.w600)),
            const SizedBox(width:4),
            const Icon(Icons.chevron_right,size:18,color:Colors.grey),
          ]),
          const SizedBox(height:14),
          ClipRRect(borderRadius:BorderRadius.circular(4),child:LinearProgressIndicator(
            value:dp,minHeight:8,backgroundColor:Colors.grey.shade200,valueColor:AlwaysStoppedAnimation(pc))),
          const SizedBox(height:8),
          Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
            Text('Day ${p.daysElapsed} of ${p.totalDays}  (${(dp*100).toStringAsFixed(0)}%)',
              style:TextStyle(fontSize:12,color:Colors.grey.shade600)),
            Text('KES ${_fmt.format(p.helbAmount)}',
              style:TextStyle(fontSize:12,fontWeight:FontWeight.w700,color:Colors.blue.shade700)),
          ]),
        ]))));
  }
}