import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/utils/droits.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kBg = Color(0xFFF7F5FA);

/// Admin : ÉVÉNEMENTS PROMOTIONNELS (Tabaski, Ramadan, fêtes…).
/// Un événement actif dont la date approche affiche un DÉCOMPTE à l'accueil.
/// (L'accueil lit la collection 'evenements' ; à défaut, calendrier par défaut.)
class EvenementsAdminPage extends StatefulWidget {
  const EvenementsAdminPage({super.key});

  @override
  State<EvenementsAdminPage> createState() => _EvenementsAdminPageState();
}

class _EvenementsAdminPageState extends State<EvenementsAdminPage>
    with PageProtegee {
  @override
  void initState() {
    super.initState();
    chargerUtilisateur();
  }

  @override
  Widget build(BuildContext context) {
    return buildAvecDroits(
      builder: (u) {
        if (!Droits.peut(u, 'evenements')) {
          return Scaffold(
            appBar: AppBar(
                title: const Text('Événements'),
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white),
            body: const Center(
                child: Text('Accès réservé aux administrateurs')),
          );
        }
        return Scaffold(
          backgroundColor: _kBg,
          appBar: AppBar(
            title: const Text('Événements & promotions'),
            backgroundColor: _kPrimary,
            foregroundColor: Colors.white,
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: _kPrimary,
            onPressed: () => _editer(null),
            child: const Icon(Icons.add, color: Colors.white),
          ),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream:
                FirebaseFirestore.instance.collection('evenements').snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: _kPrimary));
              }
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        'Aucun événement configuré.\n\nSans événement ici, '
                        'l\'app utilise le calendrier par défaut (Tabaski, '
                        'Ramadan, fêtes de fin d\'année) avec des dates '
                        'approximatives. Créez vos événements avec les VRAIES '
                        'dates pour piloter les décomptes à l\'accueil.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey)),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.all(12),
                children: docs.map((d) {
                  final data = d.data();
                  final debut = (data['dateDebut'] as Timestamp?)?.toDate();
                  final fin = (data['dateFin'] as Timestamp?)?.toDate();
                  final actif = data['actif'] as bool? ?? true;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: Text(data['emoji'] as String? ?? '🎉',
                          style: const TextStyle(fontSize: 26)),
                      title: Text(data['nom'] as String? ?? '',
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        '${debut != null ? "${debut.day}/${debut.month}/${debut.year}" : "?"}'
                        ' → ${fin != null ? "${fin.day}/${fin.month}/${fin.year}" : "?"}'
                        '${(data['reductionSuggeree'] ?? 0) > 0 ? "  ·  -${data['reductionSuggeree']}%" : ""}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Switch(
                        value: actif,
                        activeColor: _kPrimary,
                        onChanged: (v) => d.reference.update({'actif': v}),
                      ),
                      onTap: () => _editer(d),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _editer(
      QueryDocumentSnapshot<Map<String, dynamic>>? doc) async {
    final d = doc?.data() ?? {};
    final nomCtrl = TextEditingController(text: d['nom'] as String? ?? '');
    final emojiCtrl =
        TextEditingController(text: d['emoji'] as String? ?? '🎉');
    final msgCtrl = TextEditingController(
        text: d['messageMarketing'] as String? ?? '');
    final redCtrl = TextEditingController(
        text: ((d['reductionSuggeree'] as num?)?.toInt() ?? 0).toString());
    DateTime debut =
        (d['dateDebut'] as Timestamp?)?.toDate() ?? DateTime.now();
    DateTime fin = (d['dateFin'] as Timestamp?)?.toDate() ??
        DateTime.now().add(const Duration(days: 7));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(doc == null ? 'Nouvel événement' : 'Modifier'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nomCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Nom (ex: Tabaski 2026)',
                        border: OutlineInputBorder(),
                        isDense: true)),
                const SizedBox(height: 10),
                Row(children: [
                  SizedBox(
                    width: 80,
                    child: TextField(
                        controller: emojiCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Emoji',
                            border: OutlineInputBorder(),
                            isDense: true)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                        controller: redCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Réduction %',
                            border: OutlineInputBorder(),
                            isDense: true)),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(
                    controller: msgCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Message affiché',
                        border: OutlineInputBorder(),
                        isDense: true)),
                const SizedBox(height: 10),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                      'Début : ${debut.day}/${debut.month}/${debut.year}'),
                  trailing: const Icon(Icons.edit_calendar, size: 18),
                  onTap: () async {
                    final p = await showDatePicker(
                        context: ctx,
                        initialDate: debut,
                        firstDate: DateTime(2024),
                        lastDate: DateTime(2035));
                    if (p != null) setLocal(() => debut = p);
                  },
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Fin : ${fin.day}/${fin.month}/${fin.year}'),
                  trailing: const Icon(Icons.edit_calendar, size: 18),
                  onTap: () async {
                    final p = await showDatePicker(
                        context: ctx,
                        initialDate: fin,
                        firstDate: DateTime(2024),
                        lastDate: DateTime(2035));
                    if (p != null) setLocal(() => fin = p);
                  },
                ),
              ],
            ),
          ),
          actions: [
            if (doc != null)
              TextButton(
                onPressed: () async {
                  await doc.reference.delete();
                  if (ctx.mounted) Navigator.pop(ctx, false);
                },
                child: const Text('Supprimer',
                    style: TextStyle(color: Colors.red)),
              ),
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && nomCtrl.text.trim().isNotEmpty) {
      final data = {
        'nom': nomCtrl.text.trim(),
        'emoji': emojiCtrl.text.trim(),
        'messageMarketing': msgCtrl.text.trim(),
        'reductionSuggeree': int.tryParse(redCtrl.text) ?? 0,
        'dateDebut': Timestamp.fromDate(debut),
        'dateFin': Timestamp.fromDate(fin),
        'actif': true,
      };
      if (doc == null) {
        await FirebaseFirestore.instance.collection('evenements').add(data);
      } else {
        await doc.reference.update(data);
      }
    }
  }
}
