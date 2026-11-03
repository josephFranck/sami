// ignore_for_file: unused_field

import 'package:firebase_auth/firebase_auth.dart';
import 'package:sami/services/parametres_service.dart';
import 'package:sami/widgets/image_xfile.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sami/services/stockage_service.dart';
import 'package:sami/services/commission_boutique_service.dart';
import 'package:sami/models/pagne.dart';
import 'package:sami/models/categorie.dart';
import 'package:sami/utils/prix_fcfa.dart';

// ─── Alias : on utilise DecompositionFCFA de prix_fcfa.dart ─────────────────
// PrixFCFA.decomposer() gère l'arrondi au pas de 50 FCFA automatiquement
typedef _PrixPagne = DecompositionFCFA;

// ─── Page principale ──────────────────────────────────────────────────────────

class AddPagnePage extends StatefulWidget {
  /// Mode ÉDITION : pagne existant → formulaire pré-rempli, écriture
  /// en update (le MÊME formulaire riche sert création ET modification).
  final Pagne? aModifier;
  final String? boutiqueId; // si appelé depuis une boutique spécifique
  const AddPagnePage({super.key, this.boutiqueIdthis.aModifier,
  });

  @override
  State<AddPagnePage> createState() => _AddPagnePageState();
}

class _AddPagnePageState extends State<AddPagnePage> {
  // Boutiques gérées par l'utilisateur : le pagne DOIT appartenir à l'une d'elles
  List<({String id, String nom})> _mesBoutiques = [];
  String? _boutiqueChoisie;
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  // ── Contrôleurs texte ────────────────────────────────────────────────────
  final _nomController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _matiereController = TextEditingController();
  final _createurController = TextEditingController();
  final _origineController = TextEditingController();
  final _delaiController = TextEditingController();
  final _quantiteController = TextEditingController();
  final _stockController = TextEditingController(text: '1');
  final _videoController = TextEditingController();
  final _tagController = TextEditingController();

  // ── Prix ─────────────────────────────────────────────────────────────────
  final _coutAchatController = TextEditingController(text: '0');
  final _prixPlancherCtrl = TextEditingController(); // plancher promo
  final _beneficeFcfaController = TextEditingController(text: '0');
  double _beneficePct = 20.0;
  bool _beneficeActif = false;
  String _modeBenefice = 'pct'; // 'pct' ou 'fcfa'
  _PrixPagne? _prixCalc;

  // ── Médias ───────────────────────────────────────────────────────────────
  List<XFile> _imageFiles = [];
  List<String> _uploadedImageUrls = [];
  bool _isUploadingImages = false;

  // ── Listes ───────────────────────────────────────────────────────────────
  List<String> _categories = [];
  List<String> _tailles = [];
  List<String> _couleurs = [];
  List<String> _tags = [];
  Mention _mention = Mention.aucun;
  String? _billingModel; // hérité de la boutique

  // ── Catégories Firebase ──────────────────────────────────────────────────
  Map<String, String> _categorieNoms = {};
  bool _isLoadingCategories = true;

  // ── État ─────────────────────────────────────────────────────────────────
  bool _isSaving = false;

  // Options prédéfinies
  static const _taillesDispos = ['XS', 'S', 'M', 'L', 'XL', 'XXL', 'Sur mesure'];
  static const _couleursDispos = [
    'Blanc', 'Noir', 'Bleu', 'Rouge', 'Vert', 'Jaune',
    'Orange', 'Violet', 'Rose', 'Marron', 'Multicolore'
  ];

  @override
  void initState() {
    super.initState();
    // ÉDITION : pré-remplir depuis le pagne existant
    final e = widget.aModifier;
    if (e != null) {
      _nomController.text = e.nom;
      _descriptionController.text = e.description ?? '';
      _stockController.text = '${e.quantiteStock}';
      // _finance vit dans le doc brut (non exposé par le modèle)
      Pagne.pagneCollection.doc(e.id).get().then((d) {
        final cout =
            ((d.data()?['_finance'] as Map?)?['coutAchat'] as num?)?.toInt();
        if (cout != null && mounted) {
          setState(() => _coutAchatController.text = '$cout');
        }
      });
      if (e.prixPlancher != null) {
        _prixPlancherCtrl.text = '${e.prixPlancher!.toInt()}';
      }
      _boutiqueChoisie = e.boutiqueId;
    }
    _chargerMesBoutiques();
    _loadCategories();
    _loadBoutiqueConfig();
    _coutAchatController.addListener(_recalculerPrix);
    _beneficeFcfaController.addListener(_recalculerPrix);
    _recalculerPrix();
  }

  Future<void> _chargerMesBoutiques() async {
    if (widget.boutiqueId != null) {
      _boutiqueChoisie = widget.boutiqueId;
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final q = await FirebaseFirestore.instance
        .collection('boutiques')
        .where('gerants', arrayContains: uid)
        .get();
    if (!mounted) return;
    setState(() {
      _mesBoutiques = q.docs
          .map((d) => (id: d.id, nom: d.data()['nom'] as String? ?? 'Boutique'))
          .toList();
      if (_mesBoutiques.length == 1) _boutiqueChoisie = _mesBoutiques.first.id;
    });
  }

  @override
  void dispose() {
    _nomController.dispose();
    _descriptionController.dispose();
    _matiereController.dispose();
    _createurController.dispose();
    _origineController.dispose();
    _delaiController.dispose();
    _quantiteController.dispose();
    _stockController.dispose();
    _videoController.dispose();
    _tagController.dispose();
    _coutAchatController.dispose();
    _prixPlancherCtrl.dispose();
    _beneficeFcfaController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Chargements ──────────────────────────────────────────────────────────

  Future<void> _loadCategories() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('categories').get();
      final noms = <String, String>{};
      for (final doc in snap.docs) {
        noms[doc.id] = doc['nom'] as String? ?? doc.id;
      }
      setState(() {
        _categorieNoms = noms;
        _isLoadingCategories = false;
      });
    } catch (e) {
      setState(() => _isLoadingCategories = false);
    }
  }

  Future<void> _loadBoutiqueConfig() async {
    if (widget.boutiqueId == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('boutiques')
          .doc(widget.boutiqueId!)
          .get();
      if (doc.exists) {
        setState(() {
          _billingModel = doc['billingModel'] as String? ?? 'per_commission';
        });
      }
    } catch (_) {}
  }

  // ── Calcul prix ──────────────────────────────────────────────────────────

  void _recalculerPrix() {
    final cout = double.tryParse(_coutAchatController.text) ?? 0;
    double benef = 0;
    if (_beneficeActif) {
      if (_modeBenefice == 'pct') {
        benef = cout * _beneficePct / 100;
      } else {
        benef = double.tryParse(_beneficeFcfaController.text) ?? 0;
      }
    }
    setState(() {
      // Arrondi automatique au pas de 50 FCFA — contexte camerounais
      _prixCalc = PrixFCFA.decomposer(
        coutAchat: cout,
        beneficeSouhaite: benef,
        appliquerCharm: true, // prix psychologique (ex: 9 950 au lieu de 10 000)
        // MÊMES paramètres que la facturation (plus de 8 % / 70 % en dur)
        tauxCommission: ParametresService.commissionDefautPctSync,
        fraisLivraison: ParametresService.fraisLivraisonBaseSync,
        tauxGainLivreur: ParametresService.gainLivreurPctSync / 100,
      );
    });
  }

  // ── Images ───────────────────────────────────────────────────────────────

  Future<void> _selectionnerImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 80);
    if (picked.isNotEmpty) {
      setState(() => _imageFiles.addAll(picked));
    }
  }

  Future<void> _prendrePhoto() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (photo != null) {
      setState(() => _imageFiles.add(photo));
    }
  }

  /// Photos HD : abonnement PAYANT et non expiré (même lecture que la
  /// commission). Avant : `abonnement != null` — « gratuit » ou un plan
  /// expiré donnaient le HD.
  Future<bool> _boutiqueEstAbonnee() async {
    final id = _boutiqueChoisie;
    if (id == null) return false;
    final abo = await CommissionBoutiqueService.abonnementDe(id);
    return abo.prixMensuel > 0;
  }

  Future<List<String>> _uploadImages() async {
    return StockageService.uploadMultipleXFiles(
      fichiers: _imageFiles,
      dossier: 'pagnes',
      onProgress: (p) => setState(() => _progressUpload = p),
      // HD pour les boutiques ABONNÉES : photos quasi-originales —
      // un vrai avantage d'abonnement, sans pénaliser les autres.
      hd: await _boutiqueEstAbonnee(),
    );
  }

  double _progressUpload = 0;

  // ── Sauvegarde ───────────────────────────────────────────────────────────

  Future<void> _sauvegarder() async {
    if (!_formKey.currentState!.validate()) return;
    if (_imageFiles.isEmpty && _uploadedImageUrls.isEmpty) {
      _showSnack('Ajoutez au moins une image', isError: true);
      return;
    }
    if ((_prixCalc?.coutAchat ?? 0) <= 0) {
      _showSnack('Le coût d\'achat doit être supérieur à 0', isError: true);
      return;
    }

    // JAMAIS de pagne orphelin : une boutique est obligatoire (reversements,
    // notifications et « Vendu par » en dépendent).
    final boutiqueCible = widget.boutiqueId ?? _boutiqueChoisie;
    if (boutiqueCible == null) {
      _showSnack(
          _mesBoutiques.isEmpty
              ? 'Créez d\'abord votre boutique (candidature partenaire) avant de publier un pagne'
              : 'Choisissez la boutique de ce pagne',
          isError: true);
      return;
    }
    // Vérifier le CRÉDIT requis pour publier (selon l'abonnement de la boutique)
    {
      final verif = await CommissionBoutiqueService.peutPublier(boutiqueCible);
      if (!verif.autorise) {
        _showSnack(verif.raison ?? 'Crédit insuffisant pour publier', isError: true);
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      // 1. Upload images
      if (mounted) setState(() => _isUploadingImages = true);
      final imageUrls = await _uploadImages();
      if (mounted) setState(() => _isUploadingImages = false);

      // 2. Générer ID
      final id = await Pagne.getNextId();
      final prix = _prixCalc!;

      // 3. Créer le pagne
      final pagne = Pagne(
        id: id,
        nom: _nomController.text.trim(),
        description: _descriptionController.text.trim(),
        // prixParBoutique = prix final client affiché
        prixParBoutique: prix.prixFinalClient,  // multiple de 50 FCFA
        // prixDeGros = coût d'achat (pour les calculs internes)
        prixDeGros: prix.coutAchat,
        images: imageUrls,
        categories: _categories,
        tailles: _tailles,
        couleurs: _couleurs,
        matiere: _matiereController.text.trim(),
        createur: _createurController.text.trim(),
        tags: _tags,
        commentaires: {},
        noteMoyenne: 0.0,
        mention: _mention,
        origine: _origineController.text.trim(),
        disponible: (int.tryParse(_stockController.text) ?? 0) > 0,
        quantiteStock: int.tryParse(_stockController.text) ?? 0,
        quantiteDisponible: int.tryParse(_stockController.text) ?? 0,
        quantiteReservee: 0,
        quantiteMinCommande: int.tryParse(_quantiteController.text) ?? 1,
        delaiLivraison: int.tryParse(_delaiController.text) ?? 1,
        videoPresentation: _videoController.text.trim(),
      );

      // 4bis. GARDE : Firestore refuse un document > 1 Mo. En stockage
      // local (photos base64 dans le doc), on vérifie la taille totale
      // AVANT d'écrire — message clair plutôt que le jargon Firestore.
      // Cette limite ne concerne QUE le mode local (photos base64 DANS le
      // document Firestore, plafonné à 1 Mo). En mode Cloudflare R2 ou
      // Firebase Storage, les images sont des URLs : aucune limite ici.
      if (StockageService.estLocal) {
        final tailleImages =
            imageUrls.fold<int>(0, (somme, u) => somme + u.length);
        if (tailleImages > 850 * 1024) {
          _showSnack(
              'Poids total des photos : ${(tailleImages / 1024).round()} Ko '
              '(limite ${'≈'}850 Ko en stockage local — c\'est le POIDS qui '
              'compte, pas le nombre). Retirez une photo ou activez '
              'Cloudflare R2 dans Mon compte (admin) pour lever la limite.',
              isError: true);
          setState(() => _isSaving = false);
          return;
        }
      }

      // 4. Sauvegarder dans Firestore avec métadonnées financières
      final docId = widget.aModifier?.id ?? id;
      // (édition) capturer les compteurs vivant SEULEMENT dans le doc
      int? ventesAvant;
      if (widget.aModifier != null) {
        final avant = await Pagne.pagneCollection.doc(docId).get();
        ventesAvant = (avant.data()?['nombreVentes'] as num?)?.toInt();
      }
      await Pagne.pagneCollection.doc(docId).set({
        ...pagne.toMap(),
        // Métadonnées financières (non visibles client)
        '_finance': {
          'coutAchat': prix.coutAchat,
          'beneficeSouhaite': prix.beneficeSouhaite,
          'commission': prix.commission,
          'fraisLivraison': prix.fraisLivraison,
          'netBoutique': prix.netBoutique,
          'gainLivreur': prix.gainLivreur,
          'netPlateforme': prix.netPlateforme,
          'margeReel': prix.margeReelle,
        },
        'boutiqueId': boutiqueCible,
        if (_prixPlancherCtrl.text.trim().isNotEmpty)
          'prixPlancher':
              double.tryParse(_prixPlancherCtrl.text.trim()) ?? 0,
        'dateAjout': FieldValue.serverTimestamp(),
        'billingModel': _billingModel ?? 'per_commission',
      });
      // ═══ ÉDITION : PRÉSERVATION des champs vivants (le set complet
      // ci-dessus les a écrasés avec des valeurs neuves) ═══
      final e2 = widget.aModifier;
      if (e2 != null) {
        await Pagne.pagneCollection.doc(docId).update({
          if (_imageFiles.isEmpty) 'images': e2.images,
          if (ventesAvant != null) 'nombreVentes': ventesAvant,
          'noteMoyenne': e2.noteMoyenne,
          'dateAjout': e2.dateAjout,
          if (e2.prixBarre != null) 'prixBarre': e2.prixBarre,
          if (e2.promoFinLe != null) 'promoFinLe': e2.promoFinLe,
          if (e2.prixAvantPromo != null)
            'prixAvantPromo': e2.prixAvantPromo,
        });
      }

      // 5. Si modèle per_publication → débiter crédits boutique
      if (_billingModel == 'per_publication' && widget.boutiqueId != null) {
        await FirebaseFirestore.instance
            .collection('boutiques')
            .doc(widget.boutiqueId!)
            .update({'creditBalance': FieldValue.increment(-500)});
      }

      if (mounted) {
        _showSuccessDialog(prix);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Erreur : $e', isError: true);
      }
    } finally {
      setState(() {
        _isSaving = false;
        _isUploadingImages = false;
      });
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Ajouter un pagne'),
        backgroundColor: const Color(0xFF6A1B9A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else
            TextButton.icon(
              onPressed: _sauvegarder,
              icon: const Icon(Icons.check, color: Colors.white, size: 18),
              label: const Text('Publier',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.boutiqueId == null && _mesBoutiques.length > 1) ...[
              DropdownButtonFormField<String>(
                value: _boutiqueChoisie,
                decoration: const InputDecoration(
                    labelText: 'Boutique du pagne *',
                    border: OutlineInputBorder(), isDense: true),
                items: [
                  for (final b in _mesBoutiques)
                    DropdownMenuItem(value: b.id, child: Text(b.nom)),
                ],
                onChanged: (v) => setState(() => _boutiqueChoisie = v),
              ),
              const SizedBox(height: 14),
            ],
            // ── Section images ──────────────────────────────────────────
            _SectionCard(
              titre: 'Photos',
              icone: Icons.photo_library_outlined,
              child: Column(
                children: [
                  if (_imageFiles.isNotEmpty)
                    _GrilleImages(
                      images: _imageFiles,
                      onSupprimer: (i) => setState(() => _imageFiles.removeAt(i)),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _selectionnerImages,
                          icon: const Icon(Icons.photo_library, size: 18),
                          label: const Text('Galerie'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF6A1B9A),
                            side: const BorderSide(color: Color(0xFF6A1B9A)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _prendrePhoto,
                          icon: const Icon(Icons.camera_alt, size: 18),
                          label: const Text('Caméra'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF6A1B9A),
                            side: const BorderSide(color: Color(0xFF6A1B9A)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_imageFiles.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Au moins 1 photo requise',
                        style: TextStyle(
                            fontSize: 12, color: Colors.orange.shade700),
                      ),
                    ),
                ],
              ),
            ),

            // ── Section infos générales ─────────────────────────────────
            _SectionCard(
              titre: 'Informations générales',
              icone: Icons.info_outline,
              child: Column(
                children: [
                  _Champ(
                    controller: _nomController,
                    label: 'Nom du pagne *',
                    hint: 'Ex : Bazin riche brodé',
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Nom requis' : null,
                  ),
                  const SizedBox(height: 12),
                  _Champ(
                    controller: _descriptionController,
                    label: 'Description',
                    hint: 'Décrivez le pagne, sa qualité, son histoire...',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Champ(
                          controller: _matiereController,
                          label: 'Matière',
                          hint: 'Bazin, Coton...',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Champ(
                          controller: _origineController,
                          label: 'Origine',
                          hint: 'Garoua, Guinée...',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Champ(
                          controller: _delaiController,
                          label: 'Délai livraison (j)',
                          hint: '1',
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Champ(
                          controller: _stockController,
                          label: 'Stock disponible',
                          hint: 'ex: 10',
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Champ(
                          controller: _quantiteController,
                          label: 'Quantité min. commande',
                          hint: '1',
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Section PRIX (cœur du formulaire) ──────────────────────
            _SectionCard(
              titre: 'Prix & rentabilité',
              icone: Icons.calculate_outlined,
              couleurAccent: const Color(0xFF1B5E20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Coût d'achat
                  const Text(
                    'Coût d\'achat du pagne *',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _coutAchatController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _inputDeco('0').copyWith(
                      prefixText: 'FCFA  ',
                      hintText: 'Ex : 5000',
                    ),
                    validator: (v) {
                      final val = double.tryParse(v ?? '0') ?? 0;
                      return val <= 0 ? 'Entrez un coût valide' : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Prix plancher promo (optionnel)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _prixPlancherCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _inputDeco('0').copyWith(
                      prefixText: 'FCFA  ',
                      hintText: 'Votre minimum vital — vide = seuil auto',
                      helperText:
                          'Si vide : plancher automatique = coût d\'achat + '
                          'commission (jamais de vente à perte par accident).',
                      helperMaxLines: 2,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Toggle bénéfice
                  Row(
                    children: [
                      Switch(
                        value: _beneficeActif,
                        onChanged: (v) {
                          setState(() => _beneficeActif = v);
                          _recalculerPrix();
                        },
                        activeColor: const Color(0xFF1B5E20),
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Bénéfice souhaité',
                                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                            Text('Optionnel — sans bénéfice, vous récupérez le coût',
                                style: TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Champs bénéfice
                  if (_beneficeActif) ...[
                    const SizedBox(height: 12),
                    // Mode : % ou FCFA
                    Row(
                      children: [
                        _ChipMode(
                          label: 'En %',
                          actif: _modeBenefice == 'pct',
                          onTap: () {
                            setState(() => _modeBenefice = 'pct');
                            _recalculerPrix();
                          },
                        ),
                        const SizedBox(width: 8),
                        _ChipMode(
                          label: 'En FCFA',
                          actif: _modeBenefice == 'fcfa',
                          onTap: () {
                            setState(() => _modeBenefice = 'fcfa');
                            _recalculerPrix();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_modeBenefice == 'pct') ...[
                      Row(
                        children: [
                          Expanded(
                            child: Slider(
                              value: _beneficePct.clamp(0, 200),
                              min: 0,
                              max: 200,
                              divisions: 200,
                              activeColor: const Color(0xFF1B5E20),
                              onChanged: (v) {
                                setState(() => _beneficePct = v);
                                _recalculerPrix();
                              },
                            ),
                          ),
                          Container(
                            width: 64,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${_beneficePct.round()}%',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      TextFormField(
                        controller: _beneficeFcfaController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: _inputDeco('0').copyWith(
                          prefixText: 'FCFA  ',
                          hintText: 'Ex : 2000',
                          labelText: 'Bénéfice en FCFA',
                        ),
                      ),
                    ],
                  ],

                  const SizedBox(height: 16),

                  // Résultat calculateur
                  if (_prixCalc != null) _CarteResultatPrix(prix: _prixCalc!),
                ],
              ),
            ),

            // ── Section catégories & caractéristiques ───────────────────
            _SectionCard(
              titre: 'Catégories & caractéristiques',
              icone: Icons.label_outline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Catégories
                  const Text('Catégories',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  _isLoadingCategories
                      ? const LinearProgressIndicator()
                      : _BuildChipsSelection(
                          options: _categorieNoms,
                          selected: _categories,
                          onToggle: (id) => setState(() {
                            _categories.contains(id)
                                ? _categories.remove(id)
                                : _categories.add(id);
                          }),
                        ),
                  const SizedBox(height: 16),

                  // Tailles
                  const Text('Tailles disponibles',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _taillesDispos
                        .map((t) => FilterChip(
                              label: Text(t, style: const TextStyle(fontSize: 12)),
                              selected: _tailles.contains(t),
                              selectedColor:
                                  const Color(0xFF6A1B9A).withOpacity(0.15),
                              checkmarkColor: const Color(0xFF6A1B9A),
                              onSelected: (v) => setState(() {
                                v ? _tailles.add(t) : _tailles.remove(t);
                              }),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 16),

                  // Couleurs
                  const Text('Couleurs disponibles',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _couleursDispos
                        .map((c) => FilterChip(
                              label: Text(c, style: const TextStyle(fontSize: 12)),
                              selected: _couleurs.contains(c),
                              selectedColor:
                                  const Color(0xFF6A1B9A).withOpacity(0.15),
                              checkmarkColor: const Color(0xFF6A1B9A),
                              onSelected: (v) => setState(() {
                                v ? _couleurs.add(c) : _couleurs.remove(c);
                              }),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),

            // ── Section mention & tags ──────────────────────────────────
            _SectionCard(
              titre: 'Mise en avant',
              icone: Icons.star_outline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Mention spéciale',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<Mention>(
                    value: _mention,
                    decoration: _inputDeco('').copyWith(labelText: 'Mention'),
                    items: Mention.values
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(_mentionLabel(m),
                                  style: const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _mention = v!),
                  ),
                  const SizedBox(height: 16),

                  // Tags
                  const Text('Tags',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tagController,
                          decoration: _inputDeco('').copyWith(
                            hintText: 'Ajouter un tag...',
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.add, size: 18),
                              onPressed: _ajouterTag,
                            ),
                          ),
                          onSubmitted: (_) => _ajouterTag(),
                        ),
                      ),
                    ],
                  ),
                  if (_tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: _tags
                          .map((t) => Chip(
                                label: Text(t, style: const TextStyle(fontSize: 12)),
                                deleteIcon: const Icon(Icons.close, size: 14),
                                onDeleted: () => setState(() => _tags.remove(t)),
                                backgroundColor:
                                    Colors.purple.shade50,
                              ))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Vidéo
                  _Champ(
                    controller: _videoController,
                    label: 'Lien vidéo (optionnel)',
                    hint: 'https://youtube.com/...',
                    prefixIcon: Icons.play_circle_outline,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Bouton publier ──────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _sauvegarder,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle, size: 20),
                label: Text(
                  _isSaving
                      ? _isUploadingImages
                          ? 'Upload images...'
                          : 'Enregistrement...'
                      : 'Publier le pagne',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6A1B9A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _ajouterTag() {
    final tag = _tagController.text.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() => _tags.add(tag));
      _tagController.clear();
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  void _showSuccessDialog(_PrixPagne prix) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Text('Pagne publié !', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LigneResume('Prix affiché', prix.prixFinalFmt, bold: true),
            _LigneResume('Votre net', prix.netBoutiqueFmt),
            _LigneResume(
                'Votre marge', prix.margeReelleFmt),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Voir mes pagnes'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Réinitialiser le formulaire pour en ajouter un autre
              _nomController.clear();
              _descriptionController.clear();
              _coutAchatController.text = '0';
              _beneficeFcfaController.text = '0';
              setState(() {
                _imageFiles = [];
                _uploadedImageUrls = [];
                _categories = [];
                _tailles = [];
                _couleurs = [];
                _tags = [];
                _mention = Mention.aucun;
                _beneficeActif = false;
              });
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6A1B9A),
                foregroundColor: Colors.white),
            child: const Text('Ajouter un autre'),
          ),
        ],
      ),
    );
  }

  String _mentionLabel(Mention m) {
    return switch (m) {
      Mention.aucun => 'Aucune',
      Mention.coupDeCoeur => '❤️ Coup de cœur',
      Mention.meilleureVente => '🏆 Meilleure vente',
      Mention.nouveaute => '🆕 Nouveauté',
      Mention.exclusivite => '⭐ Exclusivité',
      Mention.premium => '💎 Premium',
      Mention.artisanatLocal => '🤝 Artisanat local',
      Mention.editionLimitee => '🔥 Édition limitée',
      Mention.enPromotion => '🏷️ En promotion',
      Mention.bientotDisponible => '⏳ Bientôt dispo.',
      Mention.ruptureDeStock => '❌ Rupture de stock',
    };
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF6A1B9A), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.red),
        ),
      );
}

// ─── Widget carte résultat prix ──────────────────────────────────────────────

class _CarteResultatPrix extends StatelessWidget {
  final _PrixPagne prix;
  const _CarteResultatPrix({required this.prix});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B5E20).withOpacity(0.06),
        border: Border.all(color: const Color(0xFF1B5E20).withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Prix final mis en valeur
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Prix affiché au client',
                  style: TextStyle(fontSize: 13, color: Colors.black54)),
              Text(
                prix.prixFinalFmt,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1B5E20),
                ),
              ),
            ],
          ),

          const Divider(height: 20),

          // Décomposition
          _LigneDecomp('Coût d\'achat', PrixFCFA.formater(prix.coutAchat)),
          if (prix.beneficeSouhaite > 0)
            _LigneDecomp(
              'Votre bénéfice',
              PrixFCFA.formater(prix.beneficeSouhaite),
              couleur: Colors.green.shade700,
            ),
          _LigneDecomp('Livraison incluse', PrixFCFA.formater(prix.fraisLivraison),
              muted: true),
          _LigneDecomp(
              'Commission plateforme (${prix.tauxCommission.round()}%)',
              PrixFCFA.formater(prix.commission),
              muted: true),

          const Divider(height: 16),

          // Net boutique
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Vous recevez',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              Text(
                prix.netBoutiqueFmt,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.green.shade800,
                ),
              ),
            ],
          ),

          if (prix.margeReelle > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Marge réelle : ${prix.margeReelleFmt} sur votre coût',
              style: TextStyle(fontSize: 11, color: Colors.green.shade700),
            ),
          ],
        ],
      ),
    );
  }
}

class _LigneDecomp extends StatelessWidget {
  final String label;
  final String valeur;
  final bool muted;
  final Color? couleur;

  const _LigneDecomp(this.label, this.valeur,
      {this.muted = false, this.couleur});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: muted ? Colors.black38 : Colors.black54)),
          Text(valeur,
              style: TextStyle(
                  fontSize: 12,
                  color: couleur ?? (muted ? Colors.black38 : Colors.black87))),
        ],
      ),
    );
  }
}

// ─── Widgets utilitaires ─────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String titre;
  final IconData icone;
  final Widget child;
  final Color? couleurAccent;

  const _SectionCard({
    required this.titre,
    required this.icone,
    required this.child,
    this.couleurAccent,
  });

  @override
  Widget build(BuildContext context) {
    final couleur = couleurAccent ?? const Color(0xFF6A1B9A);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: couleur.withOpacity(0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Icon(icone, color: couleur, size: 18),
                const SizedBox(width: 8),
                Text(titre,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: couleur)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _Champ extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final IconData? prefixIcon;

  const _Champ({
    required this.controller,
    required this.label,
    this.hint = '',
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.validator,
    this.prefixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 18) : null,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: Color(0xFF6A1B9A), width: 1.5),
        ),
      ),
    );
  }
}

class _ChipMode extends StatelessWidget {
  final String label;
  final bool actif;
  final VoidCallback onTap;

  const _ChipMode(
      {required this.label, required this.actif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: actif
              ? const Color(0xFF1B5E20)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: actif
                  ? const Color(0xFF1B5E20)
                  : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: actif ? Colors.white : Colors.black54,
            fontWeight: actif ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _BuildChipsSelection extends StatelessWidget {
  final Map<String, String> options;
  final List<String> selected;
  final void Function(String) onToggle;

  const _BuildChipsSelection({
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return const Text('Aucune catégorie disponible',
          style: TextStyle(color: Colors.grey, fontSize: 12));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: options.entries
          .map((e) => FilterChip(
                label: Text(e.value, style: const TextStyle(fontSize: 12)),
                selected: selected.contains(e.key),
                selectedColor:
                    const Color(0xFF6A1B9A).withOpacity(0.15),
                checkmarkColor: const Color(0xFF6A1B9A),
                onSelected: (_) => onToggle(e.key),
              ))
          .toList(),
    );
  }
}

class _GrilleImages extends StatelessWidget {
  final List<XFile> images;
  final void Function(int) onSupprimer;

  const _GrilleImages(
      {required this.images, required this.onSupprimer});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ImageXFile(
                images[i],
                width: 100,
                height: 100,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => onSupprimer(i),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close,
                      color: Colors.white, size: 12),
                ),
              ),
            ),
            if (i == 0)
              Positioned(
                bottom: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('Principale',
                      style:
                          TextStyle(color: Colors.white, fontSize: 9)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LigneResume extends StatelessWidget {
  final String label;
  final String valeur;
  final bool bold;

  const _LigneResume(this.label, this.valeur, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.black54,
                  fontWeight:
                      bold ? FontWeight.w600 : FontWeight.normal)),
          Text(valeur,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      bold ? FontWeight.bold : FontWeight.normal,
                  color: bold
                      ? const Color(0xFF6A1B9A)
                      : Colors.black87)),
        ],
      ),
    );
  }
}

// Extension privée pour formatage
extension on _PrixPagne {
  String _fmt(double v) =>
      '${v.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ')} FCFA';
}
