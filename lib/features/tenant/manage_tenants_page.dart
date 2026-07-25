import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'add_tenant_page.dart';
import 'tenant_history_page.dart';

/// Two explicit jobs in one place:
///  1. Add a NEW tenant — goes through the approval workflow.
///  2. Record a PAST tenancy for history only — no login, no approval.
class ManageTenantsPage extends StatelessWidget {
  const ManageTenantsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Manage Tenants'),
          actions: [
            IconButton(
                tooltip: 'My tenant',
                icon: const Icon(Icons.people_alt_outlined),
                onPressed: () => context.push('/my-tenant')),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Add tenant'),
            Tab(text: 'Past tenant history'),
          ]),
        ),
        body: const TabBarView(children: [
          _AddTenantSection(),
          _PastHistorySection(),
        ]),
      ),
    );
  }
}

class _AddTenantSection extends StatelessWidget {
  const _AddTenantSection();
  @override
  Widget build(BuildContext context) => Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(10)),
            child: const Text(
              'This tenant goes through the full workflow: you submit the details and '
              'documents, the society admin approves, and the tenant then receives '
              'login credentials by email.',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
          const Expanded(child: AddTenantPage()),
        ],
      );
}

class _PastHistorySection extends StatelessWidget {
  const _PastHistorySection();
  @override
  Widget build(BuildContext context) => Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(10)),
            child: const Text(
              'Record a tenancy that already ended. This is history only — no approval '
              'and no login is created.',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
          const Expanded(child: TenantHistoryPage()),
        ],
      );
}
