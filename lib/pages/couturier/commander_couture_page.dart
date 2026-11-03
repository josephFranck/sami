import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/services/parametres_service.dart';
import 'package:sami/models/panier.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:sami/models/couture.dart';
import 'package:sami/models/couturier.dart';
import 'package:sami/models/pagne.dart';
import 'package:sami/services/couture_service.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/widgets/silhouette_mesure.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kBg = Color(0xFFF7F5FA);
const _lang = Langue.fr;

/// Parcours client : faire coudre un pagne.
/// Étapes : couturier → modèle → bénéficiaire (profil) → mode mesures → confirmer.
class CommanderCouturePage extends StatefulWidget {
  final Pagne pagne;
  /// Pré-sélection (parcours inversé : modèle choisi depuis l'accueil)
  final String? modeleInitialId;
  const CommanderCouturePage(
      {super.key, required this.pagne, this.modeleInitialId});

  @override
  State<CommanderCouturePage> createState() => _CommanderCouturePageState();
}

class _CommanderCouturePageState extends State<CommanderCouturePage> {
  int _etape = 0;

  Couturier? _couturier;
  ModeleCouture? _modele;
  MesuresClient? _profil;
  ModeRencontre? _mode;
  int _nbPagnes = 1; // quantité de tissu
  bool _envoiEnCours = false; // bouton grisé + sablier pendant la commande

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: Text('Faire coudre — étape ${_etape + 1}/3'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: IndexedStack(
        index: _etape,
        children: [
          _etapeModele(),
          _etapeProfil(),
          _etapeConfirmer(),
        ],
      ),
    );
  }

  void _suivant() => setState(() => _etape = (_etape + 1).clamp(0, 2));

  // ── ÉTAPE 1 : choisir un MODÈLE (de tous les couturiers) ──────────────────
  Widget _etapeModele() {
    return Column(
      children: [
        _bandeau('Quel modèle pour ce pagne ?'),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            // Tous les modèles actifs ; choisir révèle le couturier.
            stream: ModeleCouture.collection.snapshots(),
            builder: (context, snap) {
              // Parcours inversé : pré-sélectionner le modèle venu de l'accueil
              if (_modele == null &&
                  widget.modeleInitialId != null &&
                  snap.hasData) {
                for (final d in snap.data!.docs) {
                  if (d.id == widget.modeleInitialId) {
                    WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _choisirModele(ModeleCouture.fromDoc(d)));
                    break;
                  }
                }
              }
              if (!snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: _kPrimary));
              }
              final modeles = snap.data!.docs
                  .map((d) => ModeleCouture.fromDoc(d))
                  .where((m) => m.estActif)
                  .toList();
              if (modeles.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                        'Aucun modèle disponible pour le moment. '
                        'Les couturiers ajoutent bientôt leurs créations.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600)),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: modeles.length,
                itemBuilder: (_, i) {
                  final m = modeles[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      // PHOTO du modèle : indispensable pour choisir
                      leading: m.photosExemples.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: ImageUniverselle(
                                  source: m.photosExemples.first,
                                  width: 52, height: 52, fit: BoxFit.cover),
                            )
                          : const CircleAvatar(
                              backgroundColor: _kPrimary,
                              child: Icon(Icons.checkroom, color: Colors.white),
                            ),
                      title: Text(
                          m.noms[_lang] ?? m.noms[Langue.fr] ?? 'Modèle'),
                      subtitle: Text(
                          '${_typeVetementLabel(m.typeVetement)} · '
                          'délai ${m.delaiJours} j · ${m.mesuresRequises.length} mesures'),
                      trailing: Text(
                          m.surDevis
                              ? 'Dès ${PrixFCFA.formater(m.prixBase)}'
                              : PrixFCFA.formater(m.prixBase),
                          style: const TextStyle(
                              color: _kPrimary, fontWeight: FontWeight.bold)),
                      onTap: () => _choisirModele(m),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  String _typeVetementLabel(TypeVetement t) => switch (t) {
        TypeVetement.boubou => 'Boubou',
        TypeVetement.gandoura => 'Gandoura',
        TypeVetement.robe => 'Robe',
        TypeVetement.costume => 'Costume',
        TypeVetement.chemise => 'Chemise',
        TypeVetement.jupe => 'Jupe',
        TypeVetement.pantalon => 'Pantalon',
        TypeVetement.ensemble => 'Ensemble',
        TypeVetement.autre => 'Autre',
      };

  // Au choix d'un modèle : on charge le couturier et on le présente au client.
  Future<void> _choisirModele(ModeleCouture m) async {
    setState(() => _modele = m);
    Couturier? couturier;
    try {
      final q = await Couturier.couturierCollection
          .where('utilisateurId', isEqualTo: m.couturierId)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) {
        couturier = Couturier.fromFirebaseDocument(q.docs.first);
      }
    } catch (_) {}
    _couturier = couturier;

    if (!mounted) return;
    // Présenter le couturier découvert
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Couturier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                    backgroundColor: _kPrimary,
                    child: Icon(Icons.content_cut, color: Colors.white)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                      couturier != null
                          ? '${couturier.prenom} ${couturier.nom}'
                          : 'Couturier',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ],
            ),
            if (couturier != null) ...[
              const SizedBox(height: 8),
              Text('Quartier : ${couturier.quartier}',
                  style: TextStyle(color: Colors.grey.shade600)),
            ],
            const SizedBox(height: 12),
            Text('Ce modèle sera confectionné par ce couturier.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Changer de modèle')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _suivant();
            },
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
  }

  // ── ÉTAPE 3 : choisir le bénéficiaire (profil de mesures) ─────────────────
  Widget _etapeProfil() {
    return Column(
      children: [
        _bandeau('Pour qui ? (bénéficiaire)'),
        Expanded(
          child: StreamBuilder<List<MesuresClient>>(
            stream: CoutureService.streamProfils(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                      'Impossible de charger vos profils :\n${snap.error}\n\n'
                      '→ Règles Firestore à déployer ?',
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                );
              }
              final profils = snap.data ?? [];
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  ...profils.map((p) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.person_outline,
                              color: _kPrimary),
                          title: Text(p.nomProfil ?? 'Profil'),
                          subtitle: Text('${p.valeurs.length} mesure(s) enregistrée(s)'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            setState(() {
                              _profil = p;
                              _mode = ModeRencontre.enLigne;
                            });
                            _suivant();
                          },
                        ),
                      )),
                  const SizedBox(height: 8),
                  // Nouveau profil avec mesures en ligne
                  OutlinedButton.icon(
                    onPressed: _creerProfilEnLigne,
                    icon: const Icon(Icons.add),
                    label: const Text('Nouveau profil (saisir les mesures)'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: _kPrimary,
                        side: const BorderSide(color: _kPrimary),
                        minimumSize: const Size(double.infinity, 46)),
                  ),
                  const SizedBox(height: 8),
                  // Profil "le couturier prendra les mesures"
                  ElevatedButton.icon(
                    onPressed: _profilSansMesures,
                    icon: const Icon(Icons.event_outlined),
                    label: const Text('Le couturier prendra les mesures'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 46)),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _creerProfilEnLigne() async {
    if (_modele == null) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogMesures(modele: _modele!),
    );
    if (result != null) {
      final String id;
      try {
        id = await CoutureService.sauvegarderProfil(
        nomProfil: result['nom'] as String? ?? '',
          valeurs: Map<String, double>.from(result['valeurs'] as Map),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.red,
            content: Text('Profil non enregistré : $e\n'
                '→ Vérifiez le déploiement des règles Firestore.')));
        return;
      }
      final profil = MesuresClient(
        id: id,
        clientId: '',
        nomProfil: result['nom'] as String? ?? '',
        valeurs: Map<String, double>.from(result['valeurs'] as Map),
        dateCreation: DateTime.now(),
      );
      setState(() {
        _profil = profil;
        _mode = ModeRencontre.enLigne;
      });
      _suivant();
    }
  }

  Future<void> _profilSansMesures() async {
    final nom = await _demanderNom();
    if (nom == null) return;
    final String id;
    try {
      id = await CoutureService.sauvegarderProfil(
        nomProfil: nom,
        valeurs: {},
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('Profil non enregistré : $e\n'
              '→ Vérifiez le déploiement des règles Firestore.')));
      return;
    }
    setState(() {
      _profil = MesuresClient(
        id: id,
        clientId: '',
        nomProfil: nom,
        valeurs: {},
        dateCreation: DateTime.now(),
      );
      _mode = ModeRencontre.clientVientCouturier;
    });
    _suivant();
  }

  Future<String?> _demanderNom() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nom du bénéficiaire'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: 'ex: Moi, Mon mari, Aïssa',
              border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  // ── ÉTAPE 4 : confirmer et ajouter ────────────────────────────────────────
  /// ═══ DIAGNOSTIC EMBARQUÉ ═══ l'étape 3 ne peut PLUS être blanche :
  /// soit le récap, soit l'écran orange, soit L'ERREUR EXACTE + stack.
  Widget _etapeConfirmer() {
    try {
      return _contenuConfirmer();
    } catch (e, st) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          '⛔ ERREUR ÉTAPE 3/3 (diag v2)\n\n$e\n\n'
          '${st.toString().split('\n').take(14).join('\n')}',
          style: const TextStyle(
              color: Colors.red, fontSize: 11.5, height: 1.35),
        ),
      );
    }
  }

  Widget _contenuConfirmer() {
    if (_modele == null || _couturier == null || _profil == null) {
      // JAMAIS un écran vide : dire CE qui manque et Y RAMENER.
      final manque = _modele == null
          ? 'le modèle de couture'
          : _couturier == null
              ? 'le couturier'
              : 'le bénéficiaire (profil de mesures)';
      final etapeCible = _modele == null || _couturier == null ? 0 : 1;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.info_outline,
                    size: 44, color: Colors.orange),
                const SizedBox(height: 12),
                Text('Il manque $manque pour récapituler.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: () =>
                      setState(() => _etape = etapeCible),
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: Text('Revenir à l\'étape ${etapeCible + 1}'),
                ),
              ]),
        ),
      );
    }
    // Le VRAI total : tissu × quantité + confection + les 2 courses de
    // livraison (tissu → atelier, vêtement → client). Sur devis, la
    // confection affichée est indicative jusqu'à l'accord.
    // Montant VIVANT : même source que la facturation (paramètre admin).
    final fraisLivraison2Trajets = 2 * ParametresService.fraisLivraisonBaseSync;
    final prixTissu = widget.pagne.prixParBoutique * _nbPagnes;
    final prixTotal =
        prixTissu + _modele!.prixBase + fraisLivraison2Trajets;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _bandeau('Récapitulatif'),
        const SizedBox(height: 8),
        _recapLigne('Pagne', widget.pagne.nom,
            PrixFCFA.formater(widget.pagne.prixParBoutique)),
        _recapLigne('Modèle',
            _modele!.noms[_lang] ?? _modele!.noms[Langue.fr] ?? 'Modèle',
            _modele!.surDevis
                ? 'Dès ${PrixFCFA.formater(_modele!.prixBase)}'
                : PrixFCFA.formater(_modele!.prixBase)),
        _recapLigne('Couturier', '${_couturier!.prenom} ${_couturier!.nom}', ''),
        _recapLigne('Bénéficiaire', _profil!.nomProfil ?? 'Profil', ''),
        _recapLigne(
            'Mesures',
            _mode == ModeRencontre.enLigne
                ? 'Saisies en ligne'
                : 'Prises par le couturier',
            ''),
        const Divider(height: 28),
        // ═══ COLUMN (pas Row) ═══ un Row contenant un Divider exige une
        // largeur infinie → conflit de contraintes → layout qui boucle
        // → « PagneShop ne répond pas ». Empilement vertical = correct.
        _ligneRecap('Tissu × $_nbPagnes', PrixFCFA.formater(prixTissu)),
        _ligneRecap(
            _modele!.surDevis ? 'Confection (sur devis)' : 'Confection',
            PrixFCFA.formater(_modele!.prixBase)),
        _ligneRecap('Livraison (2 trajets)',
            PrixFCFA.formater(fraisLivraison2Trajets)),
        const Divider(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Total',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(PrixFCFA.formater(prixTotal),
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: _kPrimary)),
          ],
        ),
        const SizedBox(height: 8),
        // QUANTITÉ DE TISSU (grand boubou, ensemble… = plusieurs pagnes)
        Row(children: [
          const Text('Nombre de pagnes :',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          IconButton(
              onPressed:
                  _nbPagnes > 1 ? () => setState(() => _nbPagnes--) : null,
              icon: const Icon(Icons.remove_circle_outline)),
          Text('$_nbPagnes',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          IconButton(
              onPressed:
                  _nbPagnes < 6 ? () => setState(() => _nbPagnes++) : null,
              icon: const Icon(Icons.add_circle_outline)),
        ]),
        Text('Délai de confection estimé : ${_modele!.delaiJours} jours',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        if (_modele!.surDevis)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                'Prix indicatif — le couturier confirmera le montant final '
                'après avoir vu votre demande.',
                style: TextStyle(color: Colors.orange.shade700, fontSize: 12)),
          ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _envoiEnCours
              ? null // grisé : l'utilisateur SAIT que ça travaille
              : () async {
                  setState(() => _envoiEnCours = true);
                  try {
                    await (_ajouterAuPanier)();
                  } finally {
                    if (mounted) setState(() => _envoiEnCours = false);
                  }
                },
          icon: _envoiEnCours
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.shopping_bag_outlined),
          label: Text(_envoiEnCours
              ? 'Commande en cours…'
              : 'Commander (pagne + couture)'),
          style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50)),
        ),
        const SizedBox(height: 8),
        Text(
            'Astuce : pour habiller plusieurs personnes, ajoutez ce pagne, '
            'puis recommencez avec un autre bénéficiaire.',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
            textAlign: TextAlign.center),
      ],
    );
  }

  Widget _ligneRecap(String label, String valeur) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Text(label,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
          const Spacer(),
          Text(valeur,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600)),
        ]),
      );

  Future<void> _ajouterAuPanier() async {
    // On crée directement la commande couturier (1 vêtement = 1 bénéficiaire).
    // Le pagne associé est géré via pagneId ; le paiement suivra le flux normal.
    try {
      await CoutureService.creerCommandesCouture(
        vetements: [
          VetementACoudre(
            surDevis: _modele!.surDevis,
            nombrePagnes: _nbPagnes,
            pagneId: widget.pagne.id,
            couturierId: _couturier!.utilisateurId,
            modeleId: _modele!.id,
            profilMesuresId: _profil!.id,
            mesuresSnapshot: _profil!.valeurs,
            prixConfection: _modele!.prixBase,
            modeRencontre: _mode ?? ModeRencontre.enLigne,
          ),
        ],
        methodePaiement: 'mobile_money',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Commande enregistrée : pagne réservé + couture lancée'),
          backgroundColor: Colors.green,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Erreur lors de l\'enregistrement'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  // ── Helpers UI ─────────────────────────────────────────────────────────────
  Widget _bandeau(String txt) => Container(
        width: double.infinity,
        color: _kPrimary.withOpacity(0.06),
        padding: const EdgeInsets.all(12),
        child: Text(txt,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: _kPrimary, fontSize: 15)),
      );

  Widget _recapLigne(String label, String valeur, String prix) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
                width: 90,
                child: Text(label,
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 12))),
            Expanded(
                child: Text(valeur,
                    style: const TextStyle(fontWeight: FontWeight.w500))),
            if (prix.isNotEmpty)
              Text(prix, style: const TextStyle(color: _kPrimary)),
          ],
        ),
      );
}

// ── Dialogue de saisie des mesures ───────────────────────────────────────────
class _DialogMesures extends StatefulWidget {
  final ModeleCouture modele;
  const _DialogMesures({required this.modele});

  @override
  State<_DialogMesures> createState() => _DialogMesuresState();
}

class _DialogMesuresState extends State<_DialogMesures> {
  final _nomCtrl = TextEditingController();
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, FocusNode> _focus = {};
  String? _mesureActive; // zone montrée sur la silhouette

  @override
  void initState() {
    super.initState();
    for (final m in widget.modele.mesuresRequises) {
      _ctrls[m] = TextEditingController();
      final node = FocusNode();
      node.addListener(() {
        if (node.hasFocus) setState(() => _mesureActive = m);
      });
      _focus[m] = node;
    }
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mesures du bénéficiaire'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nomCtrl,
              decoration: const InputDecoration(
                  labelText: 'Nom (ex: Moi, Aïssa)',
                  border: OutlineInputBorder(),
                  isDense: true),
            ),
            const SizedBox(height: 12),
            // MANNEQUIN : montre OÙ prendre la mesure du champ sélectionné
            // Silhouette ADAPTATIVE : réduite quand le clavier est ouvert,
            // pour que le dessin ET le champ restent visibles ensemble.
            Center(
              child: SizedBox(
                height: MediaQuery.of(context).viewInsets.bottom > 0
                    ? 110
                    : 210,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SilhouetteMesure(mesureId: _mesureActive),
                ),
              ),
            ),
            if (_mesureActive != null &&
                DefinitionMesure.catalogue[_mesureActive!]?.instruction(_lang) !=
                    null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  DefinitionMesure.catalogue[_mesureActive!]!
                      .instruction(_lang),
                  style: const TextStyle(
                      fontSize: 11, color: _kPrimary,
                      fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 8),
            ...widget.modele.mesuresRequises.map((id) {
              final def = DefinitionMesure.catalogue[id];
              final label = def?.label(_lang) ?? id;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: TextField(
                  controller: _ctrls[id],
                  focusNode: _focus[id],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: '$label (cm)',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary, foregroundColor: Colors.white),
          onPressed: () {
            final nom = _nomCtrl.text.trim();
            if (nom.isEmpty) return;
            final valeurs = <String, double>{};
            _ctrls.forEach((id, ctrl) {
              final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
              if (v != null && v > 0) valeurs[id] = v;
            });
            Navigator.pop(context, {'nom': nom, 'valeurs': valeurs});
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
