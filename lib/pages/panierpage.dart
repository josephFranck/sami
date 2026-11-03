import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:sami/services/log_service.dart';
import 'package:sami/utils/config_paiement.dart';
import 'package:sami/services/taxes_service.dart';
import 'package:sami/services/parametres_service.dart';
import 'package:sami/pages/map/selecteur_position.dart';
import 'package:sami/pages/couturier/commander_couture_page.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:sami/models/pagne.dart';
import 'package:sami/models/panier.dart';
import 'package:sami/models/utilisateur.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/services/paiement_service.dart';
import 'package:sami/widgets/connectivity_widgets.dart';
import 'package:sami/models/commande_multi.dart';
import 'package:sami/services/commande_multi_service.dart';
import 'package:sami/pages/commandes/mes_commandes_page.dart';

const _kPrimary = Color(0xFF6A1B9A);

class PanierPage extends StatefulWidget {
  final Utilisateur utilisateur;
  const PanierPage({super.key, required this.utilisateur});

  @override
  State<PanierPage> createState() => _PanierPageState();
}

class _PanierPageState extends State<PanierPage> {
  Panier? _panier;
  Map<String, Pagne> _pagnes = {};
  bool _chargement = true;
  bool _commande = false;
  String _methodePaiement = 'mobile_money';
  String _adresseLivraison = '';
  final _adresseCtrl = TextEditingController();
  final _numeroPaiementCtrl = TextEditingController();
  LatLng? _positionLivraison; // point posé sur la carte
  bool _cashLivraisonActif = true; // paramétrable (admin)
  bool _retraitPossible = false;   // au moins une boutique du panier l'offre
  double _soldeCredits = 0;
  bool _momoDeclareOk = false;     // transfert déclaré configuré+actif
  String _numMtn = '', _numOm = '', _titulaire = '';
  final _refDeclCtrl = TextEditingController();        // solde RELU en base (pas le cache)
  bool _cashAutorise = true;
  int _niveauActuel = 1;
  String _modeRecuperation = 'livreurVaBoutique';

  @override
  void initState() {
    super.initState();
    // le statique suit TOUJOURS l'état réel de la page (sinon un ancien
    // mode retrait ferait afficher 0 F de livraison à la session suivante)
    Panier.modeRetrait = _modeRecuperation == 'retraitClient';
    _chargerReglesPaiement();
    _charger();
  }

  Future<void> _charger() async {
    final panier = await Panier.charger(widget.utilisateur.id);
    final pagnesMap = <String, Pagne>{};
    // COPIE : la liste peut être nettoyée pendant les await de la boucle
    // (pagnes supprimés) → Concurrent modification sinon.
    for (final item in List.of(panier.items)) {
      final doc = await Pagne.pagneCollection.doc(item.pagneId).get();
      if (doc.exists) pagnesMap[item.pagneId] = Pagne.fromFirebaseDocument(doc);
    }
    if (mounted) setState(() { _panier = panier; _pagnes = pagnesMap; _chargement = false; });
  }

  Future<void> _chargerReglesPaiement() async {
    // Espèces à la LIVRAISON : interrupteur plateforme (pilote: oui)
    final cash = await ParametresService.cashLivraisonActif();
    // Frais de livraison VIVANTS (paramètre admin) — le récap et le total
    // du panier utilisent la même source que la facturation.
    Panier.fraisBase = await ParametresService.fraisLivraisonBase();
    // RETRAIT EN BOUTIQUE : offert seulement si TOUTES les boutiques du
    // panier ont activé l'option (sinon une partie du panier serait bloquée)
    var retrait = false;
    final ids = List.of(_panier?.items ?? []).map((i) => i.boutiqueId).whereType<String>().toSet() ?? {};
    if (ids.isNotEmpty) {
      retrait = true;
      for (final id in ids) {
        final b = await FirebaseFirestore.instance
            .collection('boutiques').doc(id).get();
        if (b.data()?['retraitEnBoutique'] != true) { retrait = false; break; }
      }
    }
    // pré-remplir le numéro MoMo depuis le profil
    final u = FirebaseAuth.instance.currentUser;
    if (u != null && _numeroPaiementCtrl.text.isEmpty) {
      final me = await FirebaseFirestore.instance
          .collection('utilisateurs').doc(u.uid).get();
      _numeroPaiementCtrl.text =
          (me.data()?['telephone'] as String? ?? '').replaceFirst('+237', '');
    }
    // SOLDE CRÉDITS : relu en base (le cache utilisateur peut dater)
    double solde = widget.utilisateur.creditBalance;
    var cashOk = true;
    // (u déjà déclaré ci-dessus pour le pré-remplissage — on le réutilise)
    if (u != null) {
      final me = await FirebaseFirestore.instance
          .collection('utilisateurs').doc(u.uid).get();
      solde = (me.data()?['creditBalance'] as num?)?.toDouble() ?? solde;
      // RÈGLE ABONNEMENT : le paiement à la livraison est un
      // AVANTAGE D'ABONNÉ — sans abonnement actif, on paie à la
      // validation (crédits ou MoMo), pas à la porte.
      final abo = me.data()?['abonnementClient'] as String?;
      final finLe = me.data()?['abonnementFinLe'];
      final aboActif = abo != null &&
          abo != 'aucun' &&
          !(finLe is Timestamp &&
              finLe.toDate().isBefore(DateTime.now()));
      cashOk = aboActif;
      _niveauActuel = (me.data()?['niveau'] as num?)?.toInt() ?? 1;
    }
    final declActif = await ParametresService.momoDeclareActif();
    final nMtn = await ParametresService.numeroMoMoMTN();
    final nOm = await ParametresService.numeroOM();
    final tit = await ParametresService.titulaireMoMo();
    if (mounted) {
      setState(() {
        _momoDeclareOk = declActif && (nMtn.isNotEmpty || nOm.isNotEmpty);
        _numMtn = nMtn; _numOm = nOm; _titulaire = tit;
        _cashLivraisonActif = cash;
        _retraitPossible = retrait;
        _soldeCredits = solde;
        _cashAutorise = cashOk;
        // basculement AUTO : crédits sélectionnés mais insuffisants →
        // Mobile Money (jamais un mode mort présélectionné)
        if (_methodePaiement == 'credits' &&
            _soldeCredits < (_panier?.total ?? 0)) {
          _methodePaiement = 'mobile_money';
        }
        if (_methodePaiement == 'cash' && !cashOk) {
          _methodePaiement = 'mobile_money';
        }
      });
    }
  }

  @override
  void dispose() {
    _adresseCtrl.dispose();
    _numeroPaiementCtrl.dispose();
    _refDeclCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text('Panier (${_panier?.nombreArticles ?? 0})'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        actions: [
          if (_panier != null && !_panier!.estVide)
            TextButton(
              onPressed: () async {
                setState(() => _panier!.vider());
                await _panier!.sauvegarder();
              },
              child: const Text('Vider', style: TextStyle(color: Colors.white70)),
            ),
        ],
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _panier == null || _panier!.estVide
              ? _buildVide()
              : _buildContenu(),
      bottomNavigationBar: _panier != null && !_panier!.estVide
          ? _buildBoutonCommande()
          : null,
    );
  }

  Widget _buildVide() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.shopping_bag_outlined, size: 80, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        const Text('Votre panier est vide', style: TextStyle(fontSize: 18, color: Colors.grey)),
        const SizedBox(height: 8),
        const Text('Explorez nos pagnes et ajoutez vos favoris',
            style: TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => Navigator.pushNamed(context, '/pagnepage'),
          style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white),
          child: const Text('Voir les pagnes'),
        ),
      ],
    ),
  );

  Widget _buildContenu() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      ...List.of(_panier!.items).map((item) => _CarteItem(
        item: item,
        pagne: _pagnes[item.pagneId],
        onQuantiteChange: (q) async {
          setState(() => _panier!.modifierQuantite(item.pagneId, q));
          await _panier!.sauvegarder();
        },
        onSupprimer: () async {
          setState(() => _panier!.supprimer(item.pagneId));
          await _panier!.sauvegarder();
        },
      )),
      const SizedBox(height: 16),
      _buildOptions(),
      const SizedBox(height: 16),
      _buildRecap(),
    ],
  );

  Widget _buildOptions() => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: Colors.grey.shade200),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Options de livraison',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 10),
          // Mode récupération
          DropdownButtonFormField<String>(
            value: _modeRecuperation,
            decoration: _inputDeco('Mode de récupération'),
            items: [
              const DropdownMenuItem(value: 'livreurVaBoutique', child: Text('Livraison à domicile')),
              if (_retraitPossible)
                const DropdownMenuItem(value: 'retraitClient', child: Text('Retrait en boutique')),
              const DropdownMenuItem(value: 'couturierLuiMeme', child: Text('Livraison couturier')),
            ],
            onChanged: (v) => setState(() {
              _modeRecuperation = v!;
              // le total (récap + facturation) suit le mode
              Panier.modeRetrait = v == 'retraitClient';
            }),
          ),
          if (_modeRecuperation != 'retraitClient') ...[
            const SizedBox(height: 10),
            // ADRESSE : saisie libre ET/OU point posé sur la carte
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _adresseCtrl,
                  decoration: _inputDeco(
                      'Adresse (quartier, repère, portail…)'),
                  onChanged: (v) => _adresseLivraison = v,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final pos = await Navigator.push<LatLng>(
                    context,
                    MaterialPageRoute(
                        builder: (_) => SelecteurPositionPage(
                            initial: _positionLivraison)),
                  );
                  if (pos != null) {
                    setState(() {
                      _positionLivraison = pos;
                      if (_adresseCtrl.text.trim().isEmpty) {
                        _adresseCtrl.text = 'Position GPS posée sur la carte';
                        _adresseLivraison = _adresseCtrl.text;
                      }
                    });
                  }
                },
                icon: Icon(
                    _positionLivraison == null
                        ? Icons.add_location_alt_outlined
                        : Icons.where_to_vote,
                    size: 18,
                    color: _positionLivraison == null ? null : Colors.green),
                label: Text(_positionLivraison == null ? '📍 Ma position sur la carte' : '✅ Position fixée',
                    style: const TextStyle(fontSize: 12)),
              ),
            ]),
          ],
          const SizedBox(height: 12),
          // ═══ MODE DE PAIEMENT : explicite, avec le numéro qui paiera ═══
          const Text('Mode de paiement',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          RadioListTile<String>(
            dense: true,
            value: 'mobile_money',
            groupValue: _methodePaiement,
            title: const Text('📱 Mobile Money (Orange / MTN)',
                style: TextStyle(fontSize: 13.5)),
            onChanged: (v) => setState(() => _methodePaiement = v!),
          ),
          if (_methodePaiement == 'mobile_money')
            Padding(
              padding: const EdgeInsets.only(left: 14, right: 14, bottom: 6),
              child: TextField(
                controller: _numeroPaiementCtrl,
                keyboardType: TextInputType.phone,
                maxLength: 9,
                decoration: _inputDeco('Numéro qui paiera (6XX XX XX XX)')
                    .copyWith(counterText: '', prefixText: '+237 '),
              ),
            ),
          // ESPÈCES : à la livraison si la plateforme l'autorise,
          // OU au retrait si TOUTES les boutiques du panier l'offrent.
          if ((_modeRecuperation != 'retraitClient' &&
                  _cashLivraisonActif) ||
              (_modeRecuperation == 'retraitClient' && _retraitPossible))
            RadioListTile<String>(
              dense: true,
              value: 'cash',
              // GRISÉ (pas caché) si la fidélité ne suffit pas — le
              // client VOIT l'option et SAIT comment la débloquer.
              groupValue: _methodePaiement,
              title: Text(
                  _modeRecuperation == 'retraitClient'
                      ? '💵 Espèces au retrait en boutique'
                      : '💵 Espèces à la livraison',
                  style: const TextStyle(fontSize: 13.5)),
              subtitle: _cashAutorise
                  ? null
                  : Text(
                      "🔒 Réservé aux abonnés — souscrivez à un abonnement pour payer à la livraison. Sans abonnement, le paiement se fait à la validation.",
                      style: const TextStyle(fontSize: 11, color: Colors.orange)),
              onChanged: _cashAutorise
                  ? (v) => setState(() => _methodePaiement = v!)
                  : null, // désactivée → grisée par Flutter,
            ),
          if (_momoDeclareOk) ...[
            RadioListTile<String>(
              dense: true,
              value: 'momo_declare',
              groupValue: _methodePaiement,
              title: const Text('📲 Transfert MoMo/OM (à déclarer)',
                  style: TextStyle(fontSize: 13.5)),
              subtitle: const Text(
                  '0 % de frais — vérifié par notre équipe avant préparation',
                  style: TextStyle(fontSize: 11)),
              onChanged: (v) => setState(() => _methodePaiement = v!),
            ),
            if (_methodePaiement == 'momo_declare')
              Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade200)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '1️⃣ Transférez ${PrixFCFA.formater(_panier?.total ?? 0)} à :'
                        '${_numMtn.isNotEmpty ? '\n     MTN MoMo : $_numMtn' : ''}'
                        '${_numOm.isNotEmpty ? '\n     Orange Money : $_numOm' : ''}'
                        '${_titulaire.isNotEmpty ? '\n     (Titulaire : $_titulaire)' : ''}'
                        '\n2️⃣ Collez la RÉFÉRENCE du SMS ci-dessous :',
                        style: const TextStyle(fontSize: 12, height: 1.5)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _refDeclCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Référence de la transaction *',
                        hintText: 'Ex : 8123456789',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          Builder(builder: (_) {
            final suffisant = _soldeCredits >= (_panier?.total ?? 0);
            return RadioListTile<String>(
              dense: true,
              value: 'credits',
              groupValue: _methodePaiement,
              title: Text('🪙 Crédits plateforme',
                  style: TextStyle(
                      fontSize: 13.5,
                      color: suffisant ? null : Colors.grey)),
              subtitle: Text(
                  suffisant
                      ? 'Solde : ${PrixFCFA.formater(_soldeCredits)}'
                      : 'Solde insuffisant (${PrixFCFA.formater(_soldeCredits)}) — payez Mobile Money',
                  style: TextStyle(
                      fontSize: 11,
                      color: suffisant
                          ? Colors.green.shade700
                          : Colors.red.shade400)),
              // insuffisant → non sélectionnable (jamais un mode mort)
              onChanged: suffisant
                  ? (v) => setState(() => _methodePaiement = v!)
                  : null,
            );
          }),
        ],
      ),
    ),
  );

  Widget _buildRecap() => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: Colors.grey.shade200),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _LigneRecap('Sous-total', PrixFCFA.formater(_panier!.sousTotal)),
          _LigneRecap('Livraison', PrixFCFA.formater(_panier!.fraisLivraison)),
          const Divider(height: 16),
          // TAXES CLIENT (si l'admin en a activé pour la cible 'client')
          FutureBuilder<(double, List<Map<String, dynamic>>)>(
            future: TaxesService.calculer(
                base: _panier!.total, cible: 'client'),
            builder: (c2, s2) {
              final t = s2.data?.$1 ?? 0;
              if (t <= 0) return const SizedBox.shrink();
              return Column(children: [
                _LigneRecap('Taxes', PrixFCFA.formater(t)),
                _LigneRecap('Total TTC',
                    PrixFCFA.formater(_panier!.total + t),
                    bold: true),
              ]);
            },
          ),
          _LigneRecap('Total', PrixFCFA.formater(_panier!.total), bold: true),
          // FIDÉLITÉ : ce que cet achat rapporte (marketing léger)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              Icon(Icons.stars, size: 13, color: Colors.amber.shade700),
              const SizedBox(width: 4),
              Text(
                  '≈ ${(_panier!.total / 1000).floor()} points fidélité à gagner',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade600)),
            ]),
          ),
        ],
      ),
    ),
  );

  Widget _buildBoutonCommande() => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
    color: Colors.white,
    child: ElevatedButton(
      onPressed: _commande ? null : _passerCommande,
      style: ElevatedButton.styleFrom(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: _commande
          ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Text('Commander · ${PrixFCFA.formater(_panier!.total)} — ${List.of(_panier!.items).map((i) => i.boutiqueId).toSet().length} boutique(s)',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    ),
  );

  Future<void> _passerCommande() async {
    if (_methodePaiement == 'mobile_money' &&
        _numeroPaiementCtrl.text.trim().length < 9) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Précisez le numéro Mobile Money qui paiera (9 chiffres)'),
          backgroundColor: Colors.red));
      return;
    }
    if (_modeRecuperation != 'retraitClient' &&
        _adresseLivraison.trim().isEmpty &&
        _positionLivraison == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entrez une adresse OU posez le point sur la carte'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _commande = true);
    // Déclarées AVANT le try : le catch (compensation) doit les voir —
    // en Dart, les variables d'un bloc try sont INVISIBLES de son catch.
    if (_methodePaiement == 'momo_declare' &&
        _refDeclCtrl.text.trim().length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Collez la référence du SMS de transfert (au moins 6 caractères).'),
          backgroundColor: Colors.orange));
      setState(() => _commande = false);
      return;
    }
    String? refPaiement;
    var creditsDebites = 0.0;
    try {
      // Construire la config de livraison par boutique
      final boutiquesIds = List.of(_panier!.items)
          .map((i) => i.boutiqueId ?? 'boutique_inconnue')
          .toSet();
      final configParBoutique = Map.fromEntries(boutiquesIds.map((bid) =>
        MapEntry(bid, ConfigLivraisonBoutique(
          boutiqueId: bid,
          typeDestination: _modeRecuperation == 'retraitClient'
              ? TypeDestination.retraitBoutique
              : TypeDestination.domicileClient,
          adresseBoutique: 'Boutique — Garoua',
        )),
      ));

      // ═══ PAIEMENT RÉEL (si activé dans l'admin) ═══
      // Mobile Money + paiements réels actifs → le client reçoit le push
      // Orange/MTN sur SON téléphone ; la commande n'est créée QU'APRÈS
      // la confirmation (webhook = source de vérité, voir GUIDE_PAIEMENT).
      // ═══ CRÉDITS : DÉBIT TRANSACTIONNEL (relit le solde, vérifie,
      // décrémente — atomique). Avant : les crédits n'étaient JAMAIS
      // débités, payer « en crédits » était gratuit !
      if (_methodePaiement == 'credits') {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        final total = _panier!.total;
        try {
          await FirebaseFirestore.instance.runTransaction((tx) async {
            final ref = FirebaseFirestore.instance
                .collection('utilisateurs').doc(uid);
            final doc = await tx.get(ref);
            final solde =
                (doc.data()?['creditBalance'] as num?)?.toDouble() ?? 0;
            if (solde < total) {
              throw Exception(
                  'Solde crédits insuffisant (${PrixFCFA.formater(solde)})');
            }
            tx.update(ref, {'creditBalance': FieldValue.increment(-total)});
          });
          creditsDebites = total;
          refPaiement = 'CREDITS';
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Paiement en crédits impossible : $e'),
                backgroundColor: Colors.red));
            setState(() => _commande = false);
          }
          return;
        }
      }
      if (_methodePaiement == 'mobile_money' &&
          await ConfigPaiement.actifs()) {
        final ok = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => PagePaiementMoMo(
              montant: _panier!.total,
              description: 'Commande PagneShop',
              clientId: widget.utilisateur.id,
              onSucces: (txId) {
                refPaiement = txId;
                if (Navigator.canPop(context)) {
                  Navigator.pop(context, true);
                }
              },
              onEchec: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context, false);
                }
              },
            ),
          ),
        );
        if (ok != true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text(
                    'Paiement non confirmé — la commande n\'a pas été créée.'),
                backgroundColor: Colors.orange));
            setState(() => _commande = false);
          }
          return;
        }
      }

      final session = await CommandeMultiService.passerCommande(
        panier: _panier!,
        clientId: widget.utilisateur.id,
        adresseLivraison: _positionLivraison != null
            ? '${_adresseLivraison.trim().isEmpty ? "Position GPS" : _adresseLivraison} '
                '[GPS ${_positionLivraison!.latitude.toStringAsFixed(6)},${_positionLivraison!.longitude.toStringAsFixed(6)}]'
            : _adresseLivraison,
        refPaiement: _methodePaiement == 'momo_declare'
            ? _refDeclCtrl.text.trim()
            : refPaiement,
        numeroPaiement: _methodePaiement == 'mobile_money'
            ? '+237${_numeroPaiementCtrl.text.trim()}'
            : null,
        gpsClientLat: _positionLivraison?.latitude,
        gpsClientLng: _positionLivraison?.longitude,
        methodePaiement: _methodePaiement,
        configParBoutique: configParBoutique,
      );
      // VIDER MAINTENANT : le seul instant sûr — la commande est créée,
      // aucun build/itération en cours sur la liste.
      _panier!.vider();
      await _panier!.sauvegarder();
      if (mounted) {
        setState(() {});
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 8),
              Text('Commande passée !'),
            ]),
            content: Text('Commande #${session.id.substring(0,6).toUpperCase()} créée.\n${session.nombreBoutiques} boutique(s) notifiée(s) — livraison en cours de planification.'),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();  // ferme le dialogue
                  Navigator.of(context).pop();  // ferme le panier
                  // Et ouvre RÉELLEMENT « Mes commandes » (le bouton fermait
                  // tout sans y aller — le client atterrissait à l'accueil).
                  Navigator.of(context).pushNamed('/commandes');
                },
                style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white),
                child: const Text('Voir mes commandes'),
              ),
            ],
          ),
        );
      }
    } catch (e, st) {
      // LA STACK EN CLAIR : la ligne exacte du coupable part au journal
      // (app_logs) ET à la console — fini le bandeau muet.
      // ignore: avoid_print
      print('══ ERREUR COMMANDE ══\n$e\n$st');
      try {
        await LogService.log('erreur_commande', details: {
          'erreur': e.toString(),
          'stack': st.toString().split('\n').take(12).join(' | '),
        });
      } catch (_) {}
      // COMPENSATION : la commande a échoué APRÈS le débit crédits →
      // on rend les crédits (jamais d'argent perdu dans les limbes).
      if (creditsDebites > 0) {
        try {
          await FirebaseFirestore.instance
              .collection('utilisateurs')
              .doc(FirebaseAuth.instance.currentUser?.uid)
              .update({'creditBalance': FieldValue.increment(creditsDebites)});
        } catch (_) {}
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Erreur : $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10)),
      );
    } finally {
      if (mounted) setState(() => _commande = false);
    }
  }

  InputDecoration _inputDeco(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
  );
}

class _CarteItem extends StatelessWidget {
  final PanierItem item;
  final Pagne? pagne;
  final ValueChanged<int> onQuantiteChange;
  final VoidCallback onSupprimer;

  const _CarteItem({
    required this.item,
    this.pagne,
    required this.onQuantiteChange,
    required this.onSupprimer,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            // Image
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 72,
                height: 72,
                child: item.pagneImage != null
                    ? ImageUniverselle(source: item.pagneImage!, fit: BoxFit.cover)
                    : Container(color: Colors.purple.shade50,
                        child: const Icon(Icons.shopping_bag, color: Color(0xFF6A1B9A))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.pagneNom, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(PrixFCFA.formater(item.prixUnitaire),
                      style: const TextStyle(color: Color(0xFF6A1B9A), fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  // Quantité
                  Row(
                    children: [
                      _BoutonQte(icone: Icons.remove, onTap: () => onQuantiteChange(item.quantite - 1)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('${item.quantite}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      _BoutonQte(icone: Icons.add, onTap: () => onQuantiteChange(item.quantite + 1)),
                      const Spacer(),
                      Text(PrixFCFA.formater(item.sousTotal),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  // Option : faire coudre ce pagne
                  if (pagne != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CommanderCouturePage(pagne: pagne!),
                          ),
                        ),
                        icon: const Icon(Icons.content_cut, size: 15),
                        label: const Text('Faire coudre',
                            style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF6A1B9A),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: const Size(0, 30),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: onSupprimer,
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoutonQte extends StatelessWidget {
  final IconData icone;
  final VoidCallback onTap;
  const _BoutonQte({required this.icone, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 26, height: 26,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icone, size: 14),
    ),
  );
}

class _LigneRecap extends StatelessWidget {
  final String label;
  final String valeur;
  final bool bold;
  const _LigneRecap(this.label, this.valeur, {this.bold = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: bold ? Colors.black87 : Colors.grey, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        Text(valeur, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: bold ? const Color(0xFF6A1B9A) : Colors.black87)),
      ],
    ),
  );
}
