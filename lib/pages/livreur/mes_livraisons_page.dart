import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:sami/utils/dates_fr.dart';
import 'package:sami/pages/livraison/scan_rapide_page.dart';
import 'package:sami/models/livraison_v2.dart';
import 'package:sami/services/qr_crypto_service.dart';
import 'package:sami/services/livraison_service.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/pages/livraison/livraison_securisee_page.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kBg = Color(0xFFF7F5FA);

/// Liste des livraisons assignées au livreur connecté.
class MesLivraisonsPage extends StatelessWidget {
  const MesLivraisonsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Veuillez vous connecter')),
      );
    }
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text('Mes livraisons'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        actions: [
          Builder(
            builder: (context) => IconButton(
              tooltip: 'Scan rapide',
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScanRapidePage()),
              ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
        // Les livraisons portent l'ID de la FICHE livreur (pas l'uid du
        // compte) : on résout d'abord la fiche via utilisateurId.
        future: FirebaseFirestore.instance
            .collection('livreurs')
            .where('utilisateurId', isEqualTo: uid)
            .limit(1)
            .get(),
        builder: (context, ficheSnap) {
          if (!ficheSnap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: _kPrimary));
          }
          final ficheId = ficheSnap.data!.docs.isNotEmpty
              ? ficheSnap.data!.docs.first.id
              : uid; // repli : anciens comptes où livreurId == uid
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('livraisons')
            .where('livreurId', isEqualTo: ficheId)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Erreur de chargement'));
          }
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: _kPrimary));
          }
          final livraisons = snap.data!.docs
              .map((d) => Livraison.fromFirebaseDocument(d))
              .toList();

          // OFFLINE-FIRST : précharger les clés QR de chaque course tant qu'on
          // a du réseau, pour pouvoir valider hors-ligne plus tard.
          for (final l in livraisons) {
            QRCryptoService.prechargerDepuisFirestore(
              livraisonId: l.id,
              role: RoleLivraison.livreur,
            );
          }

          // Tri côté client : les actives d'abord, puis par date
          livraisons.sort((a, b) {
            final aActive = _estActive(a.statut) ? 0 : 1;
            final bActive = _estActive(b.statut) ? 0 : 1;
            if (aActive != bActive) return aActive - bActive;
            return b.dateCreation.compareTo(a.dateCreation);
          });

          if (livraisons.isEmpty) {
            return _vide();
          }

          final actives =
              livraisons.where((l) => _estActive(l.statut)).toList();
          final terminees =
              livraisons.where((l) => !_estActive(l.statut)).toList();

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (actives.isNotEmpty) ...[
                _entete('À livrer', actives.length),
                ...actives.map((l) => _carte(context, l, uid)),
              ],
              if (terminees.isNotEmpty) ...[
                const SizedBox(height: 16),
                _entete('Historique', terminees.length),
                ...terminees.map((l) => _carte(context, l, uid)),
              ],
            ],
          );
        },
      );
        },
      ),
    );
  }

  static bool _estActive(StatutLivraison s) =>
      s != StatutLivraison.livre &&
      s != StatutLivraison.echec &&
      s != StatutLivraison.annule;

  Widget _entete(String titre, int n) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Text('$titre ($n)',
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: _kPrimary)),
      );

  Widget _carte(BuildContext context, Livraison l, String uid) {
    final (couleur, label) = _statutInfo(l.statut);
    final active = _estActive(l.statut);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                    l.typeLivraison == TypeLivraison.confection
                        ? Icons.checkroom
                        : Icons.shopping_bag_outlined,
                    color: _kPrimary,
                    size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.origineNom,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                            [
                              quandFr(l.brut['dateCreation'],
                                  prefixe: 'Créée le '),
                              quandFr(l.brut['dateLivraison'],
                                  prefixe: '· Livrée le '),
                            ].where((s) => s.isNotEmpty).join(' '),
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade600)),
                      ),
                    ],
                  ),
                ),
                // CE QUE JE TRANSPORTE : miniatures + noms (résumé
                // copié dans le doc livraison à la création)
                Builder(builder: (_) {
                  final arts = (l.brut['articles'] as List?)
                          ?.cast<Map<String, dynamic>>() ??
                      const [];
                  if (arts.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: arts
                          .map((a0) => Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(4),
                                    child: SizedBox(
                                      width: 48, height: 48,
                                      child: a0['image'] != null
                                          ? ImageUniverselle(
                                              source:
                                                  a0['image'] as String? ?? '',
                                              fit: BoxFit.cover)
                                          : Container(
                                              color: Colors
                                                  .purple.shade50,
                                              child: const Icon(
                                                  Icons.checkroom,
                                                  size: 12)),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                      '${a0['nom']} ×${a0['qte']}',
                                      style: const TextStyle(
                                          fontSize: 11)),
                                ],
                              ))
                          .toList(),
                    ),
                  );
                }),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: couleur.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(label,
                      style: TextStyle(
                          color: couleur,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _ligne(Icons.store_outlined, 'Retrait : ${l.origineAdresse}'),
            _ligne(Icons.location_on_outlined,
                'Livraison : ${l.destinationAdresse}'),
            _ligne(Icons.payments_outlined,
                'Montant : ${PrixFCFA.formater(l.decompositionFinanciere.prixClient)}'),
            if (active) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    // Au démarrage : passer en "en route vers la boutique"
                    if (l.statut == StatutLivraison.livreurAssigne) {
                      await LivraisonService.demarrerCourse(l.id);
                    }
                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PageLivraisonSecurisee(
                          sousCommandeId: l.commandeId,
                          livreurId: uid,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.navigation_outlined, size: 18),
                  label: Text(_actionLabel(l.statut)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
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

  Widget _ligne(IconData icone, String texte) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Expanded(
                child: Text(texte,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade700))),
          ],
        ),
      );

  String _actionLabel(StatutLivraison s) {
    switch (s) {
      case StatutLivraison.livreurAssigne:
        return 'Démarrer la course';
      case StatutLivraison.enRouteOrigine:
        return 'Scanner à la boutique';
      case StatutLivraison.articleRecupere:
      case StatutLivraison.enLivraison:
        return 'Confirmer la remise';
      default:
        return 'Traiter';
    }
  }

  (Color, String) _statutInfo(StatutLivraison s) {
    switch (s) {
      case StatutLivraison.enAttente:
        return (Colors.grey, 'En attente');
      case StatutLivraison.rechercheLibreur:
        return (Colors.orange, 'Recherche');
      case StatutLivraison.livreurAssigne:
        return (Colors.blue, 'Assignée');
      case StatutLivraison.enRouteOrigine:
        return (Colors.indigo, 'En route boutique');
      case StatutLivraison.articleRecupere:
        return (Colors.teal, 'Article récupéré');
      case StatutLivraison.enLivraison:
        return (Colors.purple, 'En livraison');
      case StatutLivraison.pretRetrait:
        return (Colors.cyan, 'Prêt retrait');
      case StatutLivraison.livre:
        return (Colors.green, 'Livré');
      case StatutLivraison.echec:
        return (Colors.red, 'Échec');
      case StatutLivraison.annule:
        return (Colors.grey, 'Annulé');
      case StatutLivraison.litige:
        return (Colors.deepOrange, 'Litige');
    }
  }

  Widget _vide() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_shipping_outlined,
                size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('Aucune livraison assignée',
                style: TextStyle(color: Colors.grey.shade500)),
            const SizedBox(height: 4),
            Text('Les nouvelles courses apparaîtront ici',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          ],
        ),
      );
}
