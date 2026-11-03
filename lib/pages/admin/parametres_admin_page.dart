import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/services/parametres_service.dart';
import 'package:sami/utils/config_paiement.dart';
import 'package:sami/services/taxes_service.dart';
import 'package:sami/utils/droits.dart';

const _kPrimary = Color(0xFF6A1B9A);

/// PARAMÈTRES DE LA PLATEFORME (admin) : politique de contacts,
/// plafond cash livreur, conformité CNI, photo finale couture.
class ParametresAdminPage extends StatefulWidget {
  const ParametresAdminPage({super.key});
  @override
  State<ParametresAdminPage> createState() => _ParametresAdminPageState();
}

class _ParametresAdminPageState extends State<ParametresAdminPage>
    with PageProtegee {
  Map<String, dynamic> _p = {};
  Map<String, dynamic> _pay = {};
  bool _charge = false;
  final _plafondCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    chargerUtilisateur();
    FirebaseFirestore.instance
        .collection('app_config')
        .doc('parametres')
        .get()
        .then((d) {
      if (mounted) {
        setState(() {
          _p = d.data() ?? {};
        });
      }
    });
    FirebaseFirestore.instance
        .collection('app_config')
        .doc('paiement')
        .get()
        .then((d) {
      if (mounted) {
        setState(() {
          _pay = d.data() ?? {};
          _plafondCtrl.text =
              ((_p['plafondCashLivreur'] as num?)?.toInt() ?? 25000)
                  .toString();
          _charge = true;
        });
      }
    });
  }

  Widget _champTxt(String label, String cle, String defaut) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextFormField(
          initialValue: (_p[cle] as String?) ?? defaut,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
              labelText: label,
              isDense: true,
              border: const OutlineInputBorder()),
          onFieldSubmitted: (v) => _maj(cle, v.trim()),
        ),
      );

  Widget _champNum(String label, String cle, String unite, num defaut) {
    final ctrl = TextEditingController(
        text: ((_p[cle] as num?) ?? defaut).toString());
    return ListTile(
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      trailing: SizedBox(
        width: 90,
        child: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.right,
          decoration: InputDecoration(suffixText: unite, isDense: true),
          onSubmitted: (v) =>
              _maj(cle, double.tryParse(v.replaceAll(',', '.')) ?? defaut),
        ),
      ),
    );
  }

  /// TEST UNIQUEMENT : vide les données transactionnelles.
  /// Conserve : utilisateurs, boutiques, couturiers, livreurs, catégories,
  /// modèles, app_config — tout ce qui est long à reconstruire.
  Future<void> _purgerCollections(List<String> collections, String nom) async {
    var total = 0;
    for (final c in collections) {
      while (true) {
        final snap = await FirebaseFirestore.instance
            .collection(c).limit(300).get();
        if (snap.docs.isEmpty) break;
        final batch = FirebaseFirestore.instance.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
        total += snap.docs.length;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$nom : $total documents supprimés'),
          backgroundColor: Colors.red));
    }
  }

  static const _toutesCollections = [
    'sessions_commande','sous_commandes','livraisons','commandes_couturier',
    'qr_secrets','notifications','alertes_agent','logs_agent','boutiques',
    'pagnes','candidatures','avis','signalements_avis','conversations',
    'messages','transactions_paiement','remboursements_a_faire','parrainages',
    'promotions','mesures','modeles_couture','reversements','recus',
    'preuves_photo','anomalies_livraison','mouvements_credits','evenements',
  ];

  /// L'admin COCHE les collections à vider — contrôle total, une par une.
  /// (Le SDK client ne sait pas LISTER les collections : liste connue.)
  Future<void> _purgeSelective() async {
    final sel = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Vider des collections'),
          content: SizedBox(
            width: double.maxFinite,
            height: 380,
            child: ListView(
              children: _toutesCollections
                  .map((c) => CheckboxListTile(
                        dense: true,
                        title: Text(c, style: const TextStyle(fontSize: 12.5)),
                        value: sel.contains(c),
                        onChanged: (v) => setD(() =>
                            v == true ? sel.add(c) : sel.remove(c)),
                      ))
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler')),
            ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white),
                onPressed:
                    sel.isEmpty ? null : () => Navigator.pop(ctx, true),
                child: Text('VIDER (${sel.length})')),
          ],
        ),
      ),
    );
    if (ok == true && sel.isNotEmpty) {
      await _purgerCollections(sel.toList(), 'Purge sélective');
    }
  }

  Future<void> _tuilePurge(String titre, String detail,
      List<String> collections) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$titre ?'),
        content: Text('IRRÉVERSIBLE.\n$detail'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('SUPPRIMER')),
        ],
      ),
    );
    if (ok == true) await _purgerCollections(collections, titre);
  }

  Future<void> _purgerDonneesTest() async {
    const collections = [
      'pagnes', 'sous_commandes', 'sessions_commande', 'commandes_couturier',
      'livraisons', 'qr_secrets', 'notifications', 'recus', 'transactions',
      'transactions_paiement', 'reversements', 'avis', 'conversations',
      'retours', 'alertes_agent', 'logs_agent', 'favoris', 'counters',
    ];
    var total = 0;
    for (final c in collections) {
      while (true) {
        final snap = await FirebaseFirestore.instance
            .collection(c).limit(300).get();
        if (snap.docs.isEmpty) break;
        final batch = FirebaseFirestore.instance.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
        total += snap.docs.length;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Purge terminée : $total documents supprimés'),
          backgroundColor: Colors.red));
    }
  }

  Future<void> _majPay(String cle, dynamic valeur) async {
    setState(() => _pay[cle] = valeur);
    await FirebaseFirestore.instance
        .collection('app_config')
        .doc('paiement')
        .set({cle: valeur}, SetOptions(merge: true));
    ConfigPaiement.invaliderCache();
  }

  Widget _champCle(String label, String cle) {
    final ctrl = TextEditingController(text: _pay[cle] as String? ?? '');
    return ListTile(
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      subtitle: TextField(
        controller: ctrl,
        obscureText: true,
        decoration: InputDecoration(
          hintText: (_pay[cle] as String? ?? '').isNotEmpty
              ? '•••••• (enregistrée — retaper pour changer)'
              : 'Coller la clé ici puis Entrée',
          isDense: true,
        ),
        onSubmitted: (v) {
          if (v.trim().isNotEmpty) _majPay(cle, v.trim());
        },
      ),
    );
  }

  Future<void> _maj(String cle, dynamic valeur) async {
    setState(() => _p[cle] = valeur);
    await FirebaseFirestore.instance
        .collection('app_config')
        .doc('parametres')
        .set({cle: valeur}, SetOptions(merge: true));
    ParametresService.invaliderCache();
  }

  @override
  Widget build(BuildContext context) {
    return buildAvecDroits(builder: (u) {
      if (!Droits.peut(u, 'parametres')) {
        return Scaffold(
            appBar: AppBar(
                title: const Text('Paramètres'),
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white),
            body: const Center(child: Text('Accès réservé')));
      }
      return Scaffold(
        backgroundColor: const Color(0xFFF7F5FA),
        appBar: AppBar(
            title: const Text('Paramètres de la plateforme'),
            backgroundColor: _kPrimary,
            foregroundColor: Colors.white),
        body: !_charge
            ? const Center(child: CircularProgressIndicator(color: _kPrimary))
            : ListView(padding: const EdgeInsets.all(14), children: [
                const Text('CONTACTS & DÉSINTERMÉDIATION',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _kPrimary)),
                SwitchListTile(
                  title: const Text('Numéros visibles par défaut',
                      style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                      'DÉSACTIVÉ (recommandé) : le contact passe par le chat '
                      'SAMI — protège la commission.',
                      style: TextStyle(fontSize: 11)),
                  value: _p['contactsVisiblesParDefaut'] as bool? ?? false,
                  activeColor: _kPrimary,
                  onChanged: (v) => _maj('contactsVisiblesParDefaut', v),
                ),
                SwitchListTile(
                  title: const Text(
                      'Abonnement payant → numéro visible (premium)',
                      style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                      'Source de revenu : afficher son numéro devient un '
                      'avantage d\'abonnement.',
                      style: TextStyle(fontSize: 11)),
                  value: _p['abonnementDebloqueContact'] as bool? ?? true,
                  activeColor: _kPrimary,
                  onChanged: (v) => _maj('abonnementDebloqueContact', v),
                ),
                const Divider(height: 24),
                const Text('LIVREURS & CASH',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _kPrimary)),
                ListTile(
                  title: const Text('Plafond d\'encours cash par livreur',
                      style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                      'Au-delà, plus de course cash assignée tant que le '
                      'livreur n\'a pas remis. 0 = désactivé.',
                      style: TextStyle(fontSize: 11)),
                  trailing: SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _plafondCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      decoration:
                          const InputDecoration(suffixText: 'F', isDense: true),
                      onSubmitted: (v) => _maj(
                          'plafondCashLivreur', double.tryParse(v) ?? 25000),
                    ),
                  ),
                ),
                const Divider(height: 24),
                const Divider(height: 30),
                const Text('⚠️ ZONE DANGER (tests uniquement)',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.red)),
                ListTile(
                  dense: true,
                  leading:
                      const Icon(Icons.checklist_rtl, color: Colors.red),
                  title: const Text('Vider des collections (sélection)…',
                      style: TextStyle(fontSize: 13)),
                  onTap: _purgeSelective,
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.storefront, color: Colors.red),
                  title: const Text('Purger les BOUTIQUES (+ leurs pagnes)',
                      style: TextStyle(fontSize: 13)),
                  onTap: () => _tuilePurge(
                      'Purger les boutiques',
                      'Boutiques, pagnes et candidatures seront effacés.',
                      ['boutiques', 'pagnes', 'candidatures']),
                ),
                ListTile(
                  dense: true,
                  leading:
                      const Icon(Icons.receipt_long, color: Colors.red),
                  title: const Text('Purger les COMMANDES en cours',
                      style: TextStyle(fontSize: 13)),
                  onTap: () => _tuilePurge(
                      'Purger les commandes',
                      'Sessions, sous-commandes, livraisons, coutures, QR et notifications.',
                      [
                        'sessions_commande',
                        'sous_commandes',
                        'livraisons',
                        'commandes_couturier',
                        'qr_secrets',
                        'notifications',
                        'alertes_agent',
                      ]),
                ),
                ListTile(
                  dense: true,
                  leading:
                      const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('Vider les données de test',
                      style: TextStyle(fontSize: 13)),
                  subtitle: const Text(
                      'Supprime commandes, livraisons, pagnes, reçus, avis… '
                      'Conserve comptes, boutiques, catégories, modèles et configuration.',
                      style: TextStyle(fontSize: 11)),
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Vider la base de TEST ?'),
                        content: const Text(
                            'Action IRRÉVERSIBLE. Tapez CONFIRMER pour valider mentalement, puis appuyez sur le bouton rouge.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Annuler')),
                          ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('TOUT SUPPRIMER')),
                        ],
                      ),
                    );
                    if (ok == true) await _purgerDonneesTest();
                  },
                ),
                const Divider(height: 30),
                const Text('TAXES (fiscalité — désactivées par défaut)',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _kPrimary)),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('app_config')
                      .doc('taxes')
                      .snapshots(),
                  builder: (c2, s2) {
                    final taxes = List<Map<String, dynamic>>.from(
                        ((s2.data?.data()?['taxes']) as List? ?? [])
                            .map((e) => Map<String, dynamic>.from(e)));
                    if (taxes.isEmpty) {
                      return ListTile(
                        dense: true,
                        title: const Text('Aucune taxe configurée',
                            style: TextStyle(fontSize: 13)),
                        trailing: TextButton(
                          onPressed: () async {
                            await TaxesService.initialiserSiVide();
                          },
                          child: const Text('Charger le catalogue (TVA…)'),
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (var i = 0; i < taxes.length; i++)
                          SwitchListTile(
                            dense: true,
                            title: Text(
                                '${taxes[i]['nom']} — ${taxes[i]['taux']}${taxes[i]['montantFixe'] == true ? ' F' : ' %'}',
                                style: const TextStyle(fontSize: 13)),
                            subtitle: Text(
                                'Cibles : ${(taxes[i]['cibles'] as List?)?.join(', ') ?? ''} · code ${taxes[i]['codeComptable']}',
                                style: const TextStyle(fontSize: 11)),
                            value: taxes[i]['actif'] == true,
                            activeColor: Colors.green,
                            onChanged: (v) async {
                              taxes[i]['actif'] = v;
                              await FirebaseFirestore.instance
                                  .collection('app_config')
                                  .doc('taxes')
                                  .set({'taxes': taxes}, SetOptions(merge: true));
                              TaxesService.invaliderCache();
                            },
                          ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                              'Une taxe active est déduite des reversements de sa cible et tracée avec son code comptable. Taux modifiables dans Firestore (app_config/taxes).',
                              style: TextStyle(fontSize: 10.5, color: Colors.grey)),
                        ),
                      ],
                    );
                  },
                ),
                const Divider(height: 24),
                const Text('PAIEMENT MOBILE MONEY',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _kPrimary)),
                SwitchListTile(
                  title: const Text('Activer les paiements RÉELS',
                      style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                      (_pay['actif'] as bool? ?? false)
                          ? '🟢 ACTIF : les clients paient via MTN MoMo / Orange Money'
                          : '⚪ Mode simulé (pilote cash) — activez quand vos clés sont prêtes',
                      style: const TextStyle(fontSize: 11)),
                  value: _pay['actif'] as bool? ?? false,
                  activeColor: Colors.green,
                  onChanged: (v) {
                    final cle = _pay['monetbilServiceKey'] as String? ?? '';
                    if (v && cle.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'Renseignez d\'abord la clé Monetbil ci-dessous')));
                      return;
                    }
                    _majPay('actif', v);
                  },
                ),
                ListTile(
                  dense: true,
                  title: const Text('Fournisseur', style: TextStyle(fontSize: 13)),
                  trailing: DropdownButton<String>(
                    value: _pay['fournisseur'] as String? ?? 'monetbil',
                    items: const [
                      DropdownMenuItem(value: 'monetbil', child: Text('Monetbil')),
                      DropdownMenuItem(value: 'cinetpay', child: Text('CinetPay')),
                    ],
                    onChanged: (v) => _majPay('fournisseur', v),
                  ),
                ),
                _champCle('Monetbil — Service Key', 'monetbilServiceKey'),
                _champCle('CinetPay — API Key (si CinetPay)', 'cinetpayApiKey'),
                _champCle('CinetPay — Site ID (si CinetPay)', 'cinetpaySiteId'),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                      'Où trouver les clés : dashboard Monetbil → Services → '
                      'Service Key (RCCM/NIU requis pour le compte marchand). '
                      'La confirmation utilise la vérification de statut '
                      'intégrée ; le webhook (GUIDE_PAIEMENT.md) reste '
                      'recommandé à l\'échelle.',
                      style: TextStyle(fontSize: 10.5, color: Colors.grey)),
                ),
                const Divider(height: 24),
                SwitchListTile(
                  dense: true,
                  title: const Text('Espèces à la livraison : clients fidèles seulement',
                      style: TextStyle(fontSize: 13)),
                  subtitle: const Text(
                      'Les nouveaux clients paient en ligne ou en crédits (anti-refus à la porte)',
                      style: TextStyle(fontSize: 11)),
                  value: _p['cashSelonFidelite'] as bool? ?? false,
                  activeColor: Colors.orange,
                  onChanged: (v) => _maj('cashSelonFidelite', v),
                ),
                _champNum('Niveau de fidélité minimum (espèces livraison)', 'niveauMinCash', '', 2),
                SwitchListTile(
                  dense: true,
                  title: const Text('Espèces à la livraison',
                      style: TextStyle(fontSize: 13)),
                  subtitle: const Text(
                      'Désactiver = Mobile Money obligatoire hors retrait boutique',
                      style: TextStyle(fontSize: 11)),
                  value: _p['cashLivraisonActif'] as bool? ?? true,
                  activeColor: Colors.green,
                  onChanged: (v) => _maj('cashLivraisonActif', v),
                ),
                const Text('FINANCES (commissions & frais)',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _kPrimary)),
                // Le carrousel d'accueil : QUI est mis en avant ?
                ListTile(
                  dense: true,
                  title: const Text('Critère du carrousel d\'accueil',
                      style: TextStyle(fontSize: 13)),
                  trailing: DropdownButton<String>(
                    value: (_p['carouselMode'] as String?) ?? 'mixte',
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(
                          value: 'mixte',
                          child: Text('Mixte équitable (rotation)',
                              style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(
                          value: 'vedettes',
                          child: Text('Vedettes (mentions)',
                              style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(
                          value: 'meilleursVentes',
                          child: Text('Meilleures ventes',
                              style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(
                          value: 'recents',
                          child: Text('Nouveautés',
                              style: TextStyle(fontSize: 12.5))),
                    ],
                    onChanged: (v) => _maj('carouselMode', v),
                  ),
                ),
                _champNum('Commission plateforme par défaut', 'commissionDefautPct', '%', 8),
                _champNum('Commission confection (couturiers sans abonnement)', 'commissionCouturePct', '%', 10),
                _champNum('Frais d\'une course de livraison', 'fraisLivraisonBase', 'F', 600),
                _champNum('Rayon de la zone de livraison (depuis la boutique)', 'rayonZoneKm', 'km', 5),
                _champNum('Supplément hors zone (par course)', 'supplementHorsZone', 'FCFA', 300),
                _champNum('Part du livreur par course', 'gainLivreurPct', '%', 70),
                _champNum('Palier fidélité 1 — seuil', 'livreurPalier1Seuil', 'courses', 20),
                _champNum('Palier fidélité 1 — bonus', 'livreurPalier1Bonus', '%', 2),
                _champNum('Palier fidélité 2 — seuil', 'livreurPalier2Seuil', 'courses', 100),
                _champNum('Palier fidélité 2 — bonus', 'livreurPalier2Bonus', '%', 5),
                _champNum('Bonus abonnement livreur', 'livreurBonusAbo', '%', 5),
                _champNum('Part livreur maximum (plafond)', 'livreurPartMax', '%', 90),
                const SizedBox(height: 6),
                const Text('ABONNEMENTS (souscription dans l\'app, transfert déclaré, vérification staff)',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.grey)),
                _champNum('Durée d\'un abonnement payé', 'abonnementDureeJours', 'jours', 30),
                _champNum('Abonnement client (espèces à la livraison) — 0 = non proposé', 'abonnementClientPrix', 'F', 0),
                _champNum('Abonnement livreur (bonus de part ci-dessus) — 0 = non proposé', 'abonnementLivreurPrix', 'F', 0),
                const Text('Les plans boutique et couturier (prix, commission) sont dans le code : AbonnementBoutique / AbonnementCouturier.',
                    style: TextStyle(fontSize: 10.5, color: Colors.grey)),
                const SizedBox(height: 6),
                const Text('LOT C — CLOUD FUNCTIONS (après déploiement, voir DEPLOIEMENT_FUNCTIONS.md)',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.grey)),
                SwitchListTile(
                  dense: true,
                  title: const Text('Scans vérifiés côté serveur', style: TextStyle(fontSize: 13)),
                  subtitle: const Text('La clé des QR ne quitte plus le serveur ; reçus signés côté serveur. Fonctions déployées requises.',
                      style: TextStyle(fontSize: 11)),
                  value: _p['scansServeur'] as bool? ?? false,
                  activeColor: Colors.green,
                  onChanged: (v) => _maj('scansServeur', v),
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('Assignation des livreurs par le serveur', style: TextStyle(fontSize: 13)),
                  subtitle: const Text('L\'agent tourne dans la Cloud Function (plus sur le téléphone du boutiquier).',
                      style: TextStyle(fontSize: 11)),
                  value: _p['assignationServeur'] as bool? ?? false,
                  activeColor: Colors.green,
                  onChanged: (v) => _maj('assignationServeur', v),
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('Connexion par SMS', style: TextStyle(fontSize: 13)),
                  subtitle: const Text('Console Firebase → Authentication → fournisseur Téléphone activé.',
                      style: TextStyle(fontSize: 11)),
                  value: _p['connexionSmsActive'] as bool? ?? false,
                  activeColor: Colors.green,
                  onChanged: (v) => _maj('connexionSmsActive', v),
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('Connexion par WhatsApp', style: TextStyle(fontSize: 13)),
                  subtitle: const Text('Fonctions déployées + secrets WHATSAPP_TOKEN / WHATSAPP_PHONE_ID.',
                      style: TextStyle(fontSize: 11)),
                  value: _p['connexionWhatsappActive'] as bool? ?? false,
                  activeColor: Colors.green,
                  onChanged: (v) => _maj('connexionWhatsappActive', v),
                ),
                const SizedBox(height: 6),
                const Text('PAIEMENT PAR TRANSFERT DÉCLARÉ (0 % de frais)',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.grey)),
                SwitchListTile(
                  dense: true,
                  title: const Text('Activer le transfert MoMo/OM déclaré',
                      style: TextStyle(fontSize: 13)),
                  subtitle: const Text(
                      'Le client transfère sur vos numéros puis déclare la référence — un agent vérifie avant préparation',
                      style: TextStyle(fontSize: 11)),
                  value: _p['momoDeclareActif'] as bool? ?? false,
                  activeColor: Colors.green,
                  onChanged: (v) => _maj('momoDeclareActif', v),
                ),
                _champTxt('Numéro MTN MoMo (recevant)', 'numeroMoMoMTN', ''),
                _champTxt('Numéro Orange Money (recevant)', 'numeroOM', ''),
                _champTxt('Nom du titulaire (affiché au client)', 'titulaireMoMo', ''),
                const SizedBox(height: 6),
                SwitchListTile(
                  dense: true,
                  title: const Text('Parrainage', style: TextStyle(fontSize: 13)),
                  subtitle: const Text(
                      'Récompenses créditées à la 1re LIVRAISON du filleul (anti-fraude)',
                      style: TextStyle(fontSize: 11)),
                  value: _p['parrainageActif'] as bool? ?? false,
                  activeColor: Colors.green,
                  onChanged: (v) => _maj('parrainageActif', v),
                ),
                _champNum('Récompense du parrain', 'recompenseParrainF', 'F', 1000),
                _champNum('Récompense du filleul', 'recompenseFilleulF', 'F', 500),
                const SizedBox(height: 6),
                const Text('IMAGES (compression à l\'upload — R2/Firebase)',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.grey)),
                _champNum('Prix barré auto (+% fictif, 0=off)', 'prixBarreAutoPct', '%', 0),
                _champNum('Qualité standard', 'imageQualitePct', '%', 60),
                _champNum('Largeur max standard', 'imageLargeurMax', 'px', 800),
                _champNum('Qualité boutiques abonnées (HD)', 'imageQualiteAbonnePct', '%', 82),
                _champNum('Largeur max abonnées (HD)', 'imageLargeurAbonneMax', 'px', 1280),
                _champNum('Frais Mobile Money entrants', 'fraisMoMoPct', '%', 2.5),
                _champNum('Frais de retrait/transfert sortant', 'fraisRetraitPct', '%', 1),
                _champNum('Marge plateforme par livraison', 'margeLivraison', 'F', 150),
                const Divider(height: 24),
                const Text('CONFORMITÉ & QUALITÉ',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _kPrimary)),
                SwitchListTile(
                  title: const Text('Supprimer la CNI après traitement',
                      style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                      'Conformité loi 2024/017 : la pièce est effacée dès que '
                      'la candidature est validée ou refusée.',
                      style: TextStyle(fontSize: 11)),
                  value: _p['supprimerCNIApresTraitement'] as bool? ?? true,
                  activeColor: _kPrimary,
                  onChanged: (v) => _maj('supprimerCNIApresTraitement', v),
                ),
                SwitchListTile(
                  title: const Text(
                      'Photo du vêtement fini obligatoire (couture)',
                      style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                      'Le couturier photographie le vêtement en le marquant '
                      '« Prête » — le client la voit avant la livraison.',
                      style: TextStyle(fontSize: 11)),
                  value: _p['photoFinaleObligatoire'] as bool? ?? true,
                  activeColor: _kPrimary,
                  onChanged: (v) => _maj('photoFinaleObligatoire', v),
                ),
              ]),
      );
    });
  }
}
