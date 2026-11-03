import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/utils/dates_fr.dart';
import 'package:sami/pages/map/carte_osm.dart';
import 'package:sami/agents/agent_livraison.dart';
import 'package:sami/models/livraison_v2.dart';

/// Dashboard du superviseur humain
/// Il voit toutes les alertes de l'agent et peut valider/rejeter
class DashboardSuperviseur extends StatelessWidget {
  const DashboardSuperviseur({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Supervision Agent IA', style: TextStyle(fontSize: 16)),
            Text('Tableau de bord', style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          // Carte des livreurs en temps réel
          IconButton(
            tooltip: 'Carte des livreurs',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => Scaffold(
                          appBar: AppBar(
                              title: const Text('Livreurs en temps réel')),
                          body: const CarteOSM(
                              marqueurs: [],
                              afficherLivreurs: true,
                              afficherPositionUtilisateur: true),
                        ))),
          ),
          // Compteur alertes urgentes
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('alertes_agent')
                .where('statut', isEqualTo: 'en_attente')
                .where('niveau', isEqualTo: AlerteNiveau.urgent.name)
                .snapshots(),
            builder: (context, snapshot) {
              final count = snapshot.data?.docs.length ?? 0;
              if (count == 0) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('$count 🚨', style: const TextStyle(color: Colors.white, fontSize: 12)),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Résumé en haut
          _CarteResume(),
          const SizedBox(height: 8),

          // Onglets
          Expanded(
            child: DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  Container(
                    color: Colors.white,
                    child: const TabBar(
                      labelColor: Color(0xFF1A237E),
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: Color(0xFF1A237E),
                      tabs: [
                        Tab(text: '🚨 Urgent'),
                        Tab(text: '⏳ À valider'),
                        Tab(text: '✅ Logs'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _ListeAlertes(niveau: AlerteNiveau.urgent),
                        _ListeAlertes(niveau: AlerteNiveau.aValider),
                        _ListeLogs(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CarteResume extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Row(
        children: [
          _StatItem(label: 'Livraisons\naujourd\'hui', valeur: '—', couleur: Colors.blue,
              collection: 'livraisons'),
          const VerticalDivider(),
          _StatItem(label: 'Auto\nagent', valeur: '—', couleur: Colors.green,
              collection: 'logs_agent'),
          const VerticalDivider(),
          _StatItem(label: 'En\nattente', valeur: '—', couleur: Colors.orange,
              collection: 'alertes_agent'),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String valeur;
  final Color couleur;
  final String collection;

  const _StatItem({
    required this.label,
    required this.valeur,
    required this.couleur,
    required this.collection,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection(collection).snapshots(),
        builder: (context, snapshot) {
          final count = snapshot.data?.docs.length ?? 0;
          return Column(
            children: [
              Text(
                '$count',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: couleur),
              ),
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.center),
            ],
          );
        },
      ),
    );
  }
}

// ─── Liste des alertes ───────────────────────────────────────────────────────

class _ListeAlertes extends StatelessWidget {
  final AlerteNiveau niveau;

  const _ListeAlertes({required this.niveau});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('alertes_agent')
          .where('niveau', isEqualTo: niveau.name)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, size: 48, color: Colors.green.shade200),
                const SizedBox(height: 8),
                Text(
                  niveau == AlerteNiveau.urgent
                      ? 'Aucune urgence 👍'
                      : 'Rien à valider',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final alerteId = docs[index].id;
            return _CarteAlerte(alerteId: alerteId, data: data, niveau: niveau);
          },
        );
      },
    );
  }
}

class _CarteAlerte extends StatelessWidget {
  final String alerteId;
  final Map<String, dynamic> data;
  final AlerteNiveau niveau;

  const _CarteAlerte({
    required this.alerteId,
    required this.data,
    required this.niveau,
  });

  @override
  Widget build(BuildContext context) {
    final livraisonId = data['livraisonId'] as String? ?? '';
    final message = data['message'] as String? ?? '';
    final decisionData = data['decisionProposee'] as Map<String, dynamic>?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: niveau == AlerteNiveau.urgent ? Colors.red.shade50 : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    niveau == AlerteNiveau.urgent ? '🚨 URGENT' : '⏳ À VALIDER',
                    style: TextStyle(
                      color: niveau == AlerteNiveau.urgent ? Colors.red : Colors.orange.shade800,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'Livraison #${livraisonId.substring(0, 6)}',
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                Text(
                  quandFr(data['dateCreation'], prefixe: '· '),
                  style: TextStyle(
                      fontSize: 10.5, color: Colors.grey.shade600),
                ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Message de l'agent
            Text(message, style: const TextStyle(fontSize: 13)),

            // Si c'est une proposition de l'agent
            if (decisionData != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('💡 Proposition agent :', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      decisionData['raisonnement'] as String? ?? '',
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                    const SizedBox(height: 4),
                    // Barre de confiance
                    _BarreConfiance(score: (decisionData['scoreConfiance'] as num?)?.toDouble() ?? 0.0),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Boutons validation
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _rejeterProposition(context, livraisonId),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Rejeter'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _validerProposition(context, alerteId, livraisonId, decisionData),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Valider'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // Urgence sans proposition — action manuelle
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _ouvrirAssignationManuelle(context, alerteId, livraisonId),
                  icon: const Icon(Icons.person_add, size: 16),
                  label: const Text('Assigner manuellement'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _validerProposition(
    BuildContext context,
    String alerteId,
    String livraisonId,
    Map<String, dynamic> decisionData,
  ) async {
    final decision = DecisionAgent.fromMap(decisionData);
    await AgentLivraison.validerProposition(
      alerteId,
      livraisonId,
      decision,
      'Validé par superviseur',
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Livraison assignée avec succès'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _rejeterProposition(BuildContext context, String livraisonId) async {
    // Ouvrir dialogue pour choisir manuellement
    _ouvrirAssignationManuelle(context, alerteId, livraisonId);
  }

  void _ouvrirAssignationManuelle(BuildContext context, String alerteId, String livraisonId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ModalAssignationManuelle(
        alerteId: alerteId,
        livraisonId: livraisonId,
      ),
    );
  }
}

class _BarreConfiance extends StatelessWidget {
  final double score;

  const _BarreConfiance({required this.score});

  @override
  Widget build(BuildContext context) {
    final couleur = score >= 0.85 ? Colors.green : score >= 0.60 ? Colors.orange : Colors.red;
    return Row(
      children: [
        const Text('Confiance : ', style: TextStyle(fontSize: 11)),
        Expanded(
          child: LinearProgressIndicator(
            value: score,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(couleur),
          ),
        ),
        const SizedBox(width: 4),
        Text('${(score * 100).toStringAsFixed(0)}%',
            style: TextStyle(color: couleur, fontWeight: FontWeight.bold, fontSize: 11)),
      ],
    );
  }
}

// ─── Modal d'assignation manuelle ────────────────────────────────────────────

class _ModalAssignationManuelle extends StatefulWidget {
  final String alerteId;
  final String livraisonId;

  const _ModalAssignationManuelle({required this.alerteId, required this.livraisonId});

  @override
  State<_ModalAssignationManuelle> createState() => _ModalAssignationManuelleState();
}

class _ModalAssignationManuelleState extends State<_ModalAssignationManuelle> {
  String? _livreurSelectionne;
  final _raisonController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16, right: 16, top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Assignation manuelle', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // Liste livreurs disponibles
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('livreurs')
                // PAS de where strict : les fiches ont DEUX conventions
                // (candidature: statut='disponible' ; promotion/tracker:
                // disponible=true ou champ absent). Filtre CLIENT tolérant.
                .snapshots(),
            builder: (context, snapshot) {
              // FILTRE CLIENT tolérant : absent = disponible ; seuls les
              // explicitement indisponibles sont écartés.
              final vus = <String>{};
              final docs = (snapshot.data?.docs ?? []).where((doc) {
                final m = doc.data() as Map<String, dynamic>;
                if (m['statut'] == 'indisponible' ||
                    m['disponible'] == false) {
                  return false;
                }
                // DÉDUP : un même livreur peut avoir PLUSIEURS fiches
                // (candidature à id aléatoire + promotion à id=uid) —
                // deux items de même valeur = assertion Flutter.
                final uid = (m['utilisateurId'] as String?) ?? doc.id;
                if (vus.contains(uid)) return false;
                vus.add(uid);
                return true;
              }).toList();
              if (docs.isEmpty) {
                return const Text('Aucun livreur disponible', style: TextStyle(color: Colors.red));
              }
              return DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Choisir un livreur',
                  border: OutlineInputBorder(),
                ),
                items: docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  // L'ID D'ASSIGNATION = le uid UTILISATEUR (les fiches
                  // de candidature ont un id de doc ALÉATOIRE — assigner
                  // doc.id casserait la reconnaissance du livreur au scan)
                  final uidLivreur =
                      (data['utilisateurId'] as String?) ?? doc.id;
                  final label = [
                    data['nom'],
                    data['prenom'],
                  ].whereType<String>().join(' ');
                  return DropdownMenuItem<String>(
                    value: uidLivreur,
                    child: Text(
                        '${label.isEmpty ? 'Livreur ${uidLivreur.substring(0, 6)}…' : label}'
                        '${data['noteMoyenne'] != null ? ' — ⭐ ${data['noteMoyenne']}/5' : ''}',
                        overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _livreurSelectionne = val),
              );
            },
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _raisonController,
            decoration: const InputDecoration(
              labelText: 'Raison du choix manuel',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _livreurSelectionne == null ? null : _confirmer,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A237E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Confirmer l\'assignation'),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Future<void> _confirmer() async {
    if (_livreurSelectionne == null) return;
    await AgentLivraison.rejeterEtAssignerManuellement(
      widget.alerteId,
      widget.livraisonId,
      _livreurSelectionne!,
      _raisonController.text.isEmpty ? 'Assignation manuelle superviseur' : _raisonController.text,
    );
    if (mounted) Navigator.pop(context);
  }
}

// ─── Logs des décisions autonomes ────────────────────────────────────────────

class _ListeLogs extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('logs_agent')
          .orderBy('dateCreation', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('Aucun log pour l\'instant'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final message = data['message'] as String? ?? '';
            final date = (data['dateCreation'] as Timestamp?)?.toDate();
            return ListTile(
              leading: const Icon(Icons.smart_toy, color: Colors.blue),
              title: Text(message, style: const TextStyle(fontSize: 13)),
              subtitle: date != null
                  ? Text(
                      '${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 11),
                    )
                  : null,
            );
          },
        );
      },
    );
  }
}
