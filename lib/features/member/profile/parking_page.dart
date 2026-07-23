import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../pulse/pulse.dart';
import 'profile_edit_api.dart';

class ParkingPage extends StatefulWidget {
  final List<Map> slots;
  final bool embedded;
  const ParkingPage({super.key, required this.slots, this.embedded = false});
  @override
  State<ParkingPage> createState() => _ParkingPageState();
}

class _ParkingPageState extends State<ParkingPage> {
  Future<void> _request({Map? existing}) async {
    final number = TextEditingController(text: '${existing?['slotNumber'] ?? ''}');
    String type = '${existing?['type'] ?? 'Open'}';
    String vehicle = '${existing?['vehicleType'] ?? 'Two-Wheeler'}';
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(
      builder: (c, setLocal) => AlertDialog(
        title: Text(existing == null ? 'Add parking request' : 'Edit parking request'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: number, decoration: const InputDecoration(labelText: 'Slot number')),
          DropdownButtonFormField<String>(initialValue: type, decoration: const InputDecoration(labelText: 'Parking type'), items: const ['Open','Covered','Stilt'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(), onChanged:(v)=>setLocal(()=>type=v!)),
          DropdownButtonFormField<String>(initialValue: vehicle, decoration: const InputDecoration(labelText: 'Vehicle type'), items: const ['Two-Wheeler','Four-Wheeler'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(), onChanged:(v)=>setLocal(()=>vehicle=v!)),
          const SizedBox(height: 10),
          const Text('The change becomes visible only after admin approval.', style: TextStyle(fontSize: 12)),
        ]),
        actions: [TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Send for approval'))],
      ),
    ));
    if (ok != true || number.text.trim().isEmpty || !mounted) return;
    await submitProfileEditRequest(context.read<Dio>(), {
      'section': 'Parking',
      'action': existing == null ? 'Add' : 'Edit',
      'payload': {
        if (existing != null) 'existingSlotNumber': existing['slotNumber'],
        'slotNumber': number.text.trim(),
        'type': type,
        'vehicleType': vehicle,
        'monthlyBilling': type != 'Stilt',
      },
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Parking request sent for admin approval')));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final body = ListView(padding: const EdgeInsets.all(20), children: [
      Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed:()=>_request(), icon:const Icon(Icons.add), label:const Text('Add parking'))),
      const SizedBox(height: 12),
      if (widget.slots.isEmpty) Text('No parking slots yet', style: TextStyle(color:t.fg5))
      else ...widget.slots.map((s)=>Card(child:ListTile(
        title:Text('${s['slotNumber'] ?? '—'}'),
        subtitle:Text('${s['type'] ?? '—'} · ${s['vehicleType'] ?? '—'}'),
        trailing:IconButton(icon:const Icon(Icons.edit_outlined), onPressed:()=>_request(existing:s)),
      ))),
    ]);
    if (widget.embedded) return body;
    return Scaffold(appBar:AppBar(title:const Text('Parking')), body:body);
  }
}
