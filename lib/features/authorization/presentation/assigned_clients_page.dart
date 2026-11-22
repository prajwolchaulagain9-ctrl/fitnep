import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes/route_access_gate.dart';
import '../data/authorization_repository.dart';

class AssignedClientsPage extends ConsumerStatefulWidget {
  const AssignedClientsPage({super.key});
  @override
  ConsumerState<AssignedClientsPage> createState() =>
      _AssignedClientsPageState();
}

class _AssignedClientsPageState extends ConsumerState<AssignedClientsPage> {
  late Future<List<Map<String, dynamic>>> clients;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    clients = ref
        .read(authorizationRepositoryProvider)
        .all('clients/assigned', 'clients');
  }

  @override
  Widget build(BuildContext context) {
    final canRead = AuthorizationService(
      ref.watch(routeSessionProvider).value?.role,
    ).hasPermission('view_assigned_client_records');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assigned clients'),
        actions: [
          IconButton(
            onPressed: () => setState(_load),
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder(
        future: clients,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(snapshot.error.toString()),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const Center(
              child: Text('No active clients are assigned to you.'),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final client in snapshot.data!)
                Card(
                  child: ListTile(
                    title: Text(client['full_name'] as String),
                    subtitle: Text(client['email'] as String),
                    trailing: canRead ? const Icon(Icons.chevron_right) : null,
                    onTap: canRead
                        ? () => context.push(
                            '/care/clients/${Uri.encodeComponent(client['id'] as String)}/records',
                          )
                        : null,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
