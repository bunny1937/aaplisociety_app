import 'package:flutter/material.dart';
import 'contact_page.dart';
import 'emergency_contact_page.dart';
import 'family_members_page.dart';
import 'flat_details_page.dart';
import 'parking_page.dart';

/// Single page hosting the 5 profile sections as tabs, replacing the old
/// 5-separate-tiles/5-separate-pages navigation.
class BasicDetailsPage extends StatelessWidget {
  final Map? member;
  final String? flatNo;
  final String? wing;
  final String? email;
  final bool canEdit;
  final List<Map> parkingSlots;
  final List<Map> familyMembers;
  const BasicDetailsPage({
    super.key,
    required this.member,
    this.flatNo,
    this.wing,
    this.email,
    required this.canEdit,
    required this.parkingSlots,
    required this.familyMembers,
  });
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Basic details'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Flat'),
              Tab(text: 'Contact'),
              Tab(text: 'Parking'),
              Tab(text: 'Family'),
              Tab(text: 'Emergency'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            FlatDetailsPage(
                member: member, flatNo: flatNo, wing: wing, embedded: true),
            ContactPage(
                member: member, email: email, canEdit: canEdit, embedded: true),
            ParkingPage(slots: parkingSlots, embedded: true),
            FamilyMembersPage(
                members: familyMembers, canEdit: canEdit, embedded: true),
            EmergencyContactPage(
                member: member, canEdit: canEdit, embedded: true),
          ],
        ),
      ),
    );
  }
}
