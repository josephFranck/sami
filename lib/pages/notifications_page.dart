import 'package:flutter/material.dart';
import 'package:sami/services/notification_service.dart';

const _kPrimary = Color(0xFF6A1B9A);

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FA),
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: NotificationService.toutMarquerLues,
            child: const Text('Tout lire',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: NotificationService.mesNotifs(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: _kPrimary));
          }
          final docs = snap.data!;
          if (docs.isEmpty) {
            return const Center(
                child: Text('Aucune notification',
                    style: TextStyle(color: Colors.grey)));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final d = docs[i].data();
              final lue = d['lue'] as bool? ?? false;
              return Card(
                color: lue ? Colors.white : _kPrimary.withOpacity(0.05),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                      lue
                          ? Icons.notifications_none
                          : Icons.notifications_active,
                      color: lue ? Colors.grey : _kPrimary),
                  title: Text(d['titre'] as String? ?? '',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              lue ? FontWeight.normal : FontWeight.bold)),
                  subtitle: Text(d['message'] as String? ?? '',
                      style: const TextStyle(fontSize: 12)),
                  onTap: () {
                    NotificationService.marquerLue(docs[i].id);
                    final route = d['route'] as String?;
                    if (route != null && route.isNotEmpty) {
                      Navigator.pushNamed(context, route);
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
