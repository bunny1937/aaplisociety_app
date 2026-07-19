import 'package:flutter/material.dart';
import 'profile_section_widgets.dart';

/// Read-only — flat details are admin/web-managed, no edit-request workflow.
class FlatDetailsPage extends StatelessWidget {
  final Map? member;
  final String? flatNo;
  final String? wing;
  const FlatDetailsPage({super.key, required this.member, this.flatNo, this.wing});

  @override
  Widget build(BuildContext context) {
    final carpetArea = member?['carpetAreaSqft'];
    final builtUpArea = member?['builtUpAreaSqft'];
    final areaText = carpetArea != null
        ? '$carpetArea sqft (carpet)${builtUpArea != null ? ' · $builtUpArea sqft (built-up)' : ''}'
        : null;
    final votingRights = member?['hasVotingRights'];
    final votingText = votingRights == null ? null : (votingRights == true ? 'Eligible' : 'Not eligible');

    return Scaffold(
      appBar: AppBar(title: const Text('Flat details')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ProfileInfoRow(
            label: 'Flat',
            value: flatNo != null ? '$flatNo${wing != null && wing!.isNotEmpty ? ' ($wing wing)' : ''}' : null,
          ),
          ProfileInfoRow(label: 'Type', value: member?['flatType']?.toString()),
          ProfileInfoRow(label: 'Ownership', value: member?['ownershipType']?.toString()),
          ProfileInfoRow(label: 'Carpet area', value: areaText),
          ProfileInfoRow(label: 'Voting rights', value: votingText),
        ],
      ),
    );
  }
}
