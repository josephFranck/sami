import 'dart:io';
import 'package:sami/widgets/image_xfile.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sami/services/stockage_service.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:sami/models/couture.dart';
import 'package:sami/models/couture_options.dart';
import 'package:sami/utils/prix_fcfa.dart';
import 'package:sami/services/langue_service.dart';
import 'package:sami/l10n/tr.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kBg = Color(0xFFF7F5FA);
// Langue des libellés de modèles/mesures (catalogues FR/EN) : celle de l'app.
Langue get _lang => LangueService.instance.estAnglais ? Langue.en : Langue.fr;

/// Création / édition d'un modèle de couture par le couturier.
/// Supporte les DEUX modes : prix fixe OU sur devis (prix négocié après demande).
class CreerModelePage extends StatefulWidget {
  final String couturierId;
  final ModeleCouture? modeleExistant; // si édition
  const CreerModelePage({
    super.key,
    required this.couturierId,
    this.modeleExistant,
  });

  @override
  State<CreerModelePage> createState() => _CreerModelePageState();
}

class _CreerModelePageState extends State<CreerModelePage> {
  final _nomCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _prixCtrl = TextEditingController();
  final _delaiCtrl = TextEditingController(text: '3');

  TypeVetement _type = TypeVetement.boubou;
  bool _surDevis = false;
  final Set<String> _mesures = {};
  final Set<ModeRencontre> _modes = {ModeRencontre.clientVientCouturier};
  bool _enCours = false;
  final List<XFile> _nouvellesPhotos = [];
  List<String> _photosExistantes = [];
  double _progressUpload = 0;
  bool _negociationAutorisee = false;
  bool _aboCharge = false;
  int _limiteModeles = 3; // limite du niveau gratuit par défaut

  @override
  void initState() {
    super.initState();
    _chargerAbonnement();
    final m = widget.modeleExistant;
    if (m != null) {
      _nomCtrl.text = m.noms[_lang] ?? '';
      _descCtrl.text = m.descriptions[_lang] ?? '';
      _prixCtrl.text = m.prixBase.toStringAsFixed(0);
      _delaiCtrl.text = m.delaiJours.toString();
      _type = m.typeVetement;
      _surDevis = m.surDevis;
      _mesures.addAll(m.mesuresRequises);
      _modes
        ..clear()
        ..addAll(m.modesDisponibles);
      _photosExistantes = List<String>.from(m.photosExemples);
    }
  }

  Future<void> _chargerAbonnement() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('couturiers')
          .where('utilisateurId', isEqualTo: widget.couturierId)
          .limit(1)
          .get();
      String type = 'gratuit';
      if (doc.docs.isNotEmpty) {
        type = doc.docs.first.data()['typeAbonnement'] as String? ?? 'gratuit';
      }
        // EXPIRATION : un palier payé a une FIN. Champ optionnel
        // 'abonnementFinLe' (posé à la souscription/à la main) —
        // dépassé ⇒ retour au gratuit, silencieusement.
        final finLe = doc.docs.isNotEmpty
            ? doc.docs.first.data()['abonnementFinLe']
            : null;
        if (finLe is Timestamp &&
            finLe.toDate().isBefore(DateTime.now())) {
          type = 'gratuit';
        }
      final abo = AbonnementCouturier.catalogue[
          TypeAbonnementCouturier.values.firstWhere((e) => e.name == (type), orElse: () => TypeAbonnementCouturier.values.first)];
      if (mounted) {
        setState(() {
          _negociationAutorisee = abo?.negociationAutorisee ?? false;
          _limiteModeles = abo?.limiteModeles ?? 3;
          _aboCharge = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _aboCharge = true);
    }
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _descCtrl.dispose();
    _prixCtrl.dispose();
    _delaiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final edition = widget.modeleExistant != null;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: Text(edition ? Tr.s.modifierModele : Tr.s.nouveauModele),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _label(Tr.s.nomModele),
          TextField(
            controller: _nomCtrl,
            decoration: _deco(Tr.s.exBoubouBrodeGrandModele),
          ),
          const SizedBox(height: 16),
          _label(Tr.s.typeVetement),
          Wrap(
            spacing: 8,
            children: TypeVetement.values.map((t) {
              final sel = _type == t;
              return ChoiceChip(
                label: Text(_typeLabel(t)),
                selected: sel,
                selectedColor: _kPrimary.withOpacity(0.2),
                onSelected: (_) => setState(() => _type = t),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          _label(Tr.s.descriptionOptionnel),
          TextField(
            controller: _descCtrl,
            maxLines: 2,
            decoration: _deco(Tr.s.detailsFinitionsTissusConseilles),
          ),
          const SizedBox(height: 20),

          // Mode de tarification : prix fixe OU sur devis
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  value: _surDevis,
                  activeColor: _kPrimary,
                  contentPadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Text(Tr.s.surDevis),
                      if (!_negociationAutorisee) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.lock_outline,
                            size: 14, color: Colors.orange),
                      ],
                    ],
                  ),
                  subtitle: Text(
                      !_negociationAutorisee
                          ? Tr.s.reserveAbonnementsProfessionnelExpert
                          : _surDevis
                              ? Tr.s.prixSeraNegocieApresDemande
                              : Tr.s.prixFixeAfficheClient,
                      style: const TextStyle(fontSize: 12)),
                  onChanged: !_negociationAutorisee
                      ? null
                      : (v) => setState(() => _surDevis = v),
                ),
                if (!_negociationAutorisee && _aboCharge)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          Navigator.pushNamed(context, '/abonnements'),
                      icon: const Icon(Icons.workspace_premium,
                          size: 16, color: _kPrimary),
                      label: Text(Tr.s.debloquerNegociation,
                          style: TextStyle(fontSize: 12, color: _kPrimary)),
                    ),
                  ),
                const SizedBox(height: 8),
                _label(_surDevis ? Tr.s.prixIndicatifPartir : Tr.s.prixFixe),
                TextField(
                  controller: _prixCtrl,
                  keyboardType: TextInputType.number,
                  decoration: _deco(Tr.s.ex8000).copyWith(suffixText: 'FCFA'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          _label(Tr.s.delaiConfectionJours),
          TextField(
            controller: _delaiCtrl,
            keyboardType: TextInputType.number,
            decoration: _deco(Tr.s.ex3),
          ),
          const SizedBox(height: 20),

          _label(Tr.s.photosModeleExemples),
          Text(Tr.s.montrezVosRealisationsPourAttirer,
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          SizedBox(
            height: 98, // +8 : tuait l'overflow de 6 px
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // Photos existantes (édition)
                ..._photosExistantes.map((url) => _vignette(
                      ImageUniverselle(source: url, width: 84, height: 84,
                          fit: BoxFit.cover),
                      onSupprimer: () =>
                          setState(() => _photosExistantes.remove(url)),
                    )),
                // Nouvelles photos sélectionnées
                ..._nouvellesPhotos.map((x) => _vignette(
                      ImageXFile(x,
                          width: 84, height: 84, fit: BoxFit.cover),
                      onSupprimer: () =>
                          setState(() => _nouvellesPhotos.remove(x)),
                    )),
                // Boutons d'ajout
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: _ajouterPhotos,
                      icon: const Icon(Icons.photo_library_outlined,
                          color: _kPrimary),
                    ),
                    IconButton(
                      onPressed: _prendrePhoto,
                      icon: const Icon(Icons.camera_alt_outlined,
                          color: _kPrimary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_enCours && _progressUpload > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(value: _progressUpload),
            ),
          const SizedBox(height: 20),

          _label(Tr.s.mesuresNecessaires),
          Text(Tr.s.cochezMesuresDontVousAvez,
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          ...DefinitionMesure.catalogue.entries.map((e) {
            final id = e.key;
            return CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: _kPrimary,
              value: _mesures.contains(id),
              title: Text(e.value.label(_lang)),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _mesures.add(id);
                } else {
                  _mesures.remove(id);
                }
              }),
            );
          }),
          const SizedBox(height: 16),

          _label(Tr.s.commentPrenezVousMesures),
          ...ModeRencontre.values.map((m) {
            return CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: _kPrimary,
              value: _modes.contains(m),
              title: Text(_modeLabel(m)),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _modes.add(m);
                } else {
                  _modes.remove(m);
                }
              }),
            );
          }),
          const SizedBox(height: 28),

          ElevatedButton(
            onPressed: _enCours ? null : _enregistrer,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
            ),
            child: _enCours
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text(edition ? Tr.s.enregistrer : Tr.s.publierModele),
          ),
        ],
      ),
    );
  }

  Future<void> _ajouterPhotos() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 80);
    if (picked.isNotEmpty) setState(() => _nouvellesPhotos.addAll(picked));
  }

  Future<void> _prendrePhoto() async {
    final picker = ImagePicker();
    final photo =
        await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (photo != null) setState(() => _nouvellesPhotos.add(photo));
  }

  Future<void> _enregistrer() async {
    final nom = _nomCtrl.text.trim();
    if (nom.isEmpty) {
      _snack(Tr.s.donnezNomModele);
      return;
    }
    final prix = double.tryParse(_prixCtrl.text.replaceAll(',', '.')) ?? 0;
    if (!_surDevis && prix <= 0) {
      _snack(Tr.s.indiquezPrixOuActivezSur);
      return;
    }
    if (_mesures.isEmpty && !_modes.contains(ModeRencontre.clientVientCouturier)) {
      _snack(Tr.s.choisissezMoinsMesureOuPrise);
      return;
    }
    if (_modes.isEmpty) {
      _snack(Tr.s.choisissezMoinsModePriseMesures);
      return;
    }

    // LIMITE DE MODÈLES selon l'abonnement (levier commercial) :
    // à la création seulement, compter les modèles existants du couturier.
    if (widget.modeleExistant == null) {
      try {
        final q = await ModeleCouture.collection
            .where('couturierId', isEqualTo: widget.couturierId)
            .get();
        if (q.docs.length >= _limiteModeles) {
          _snack(Tr.s.limiteAtteinteModelesPassezAbonnement(_limiteModeles));
          if (mounted) {
            Navigator.pushNamed(context, '/abonnements');
          }
          return;
        }
      } catch (_) {}
    }

    setState(() => _enCours = true);

    // Upload des nouvelles photos (mode base64 local pour l'instant)
    List<String> photos = List.from(_photosExistantes);
    if (_nouvellesPhotos.isNotEmpty) {
      try {
        final urls = await StockageService.uploadMultipleXFiles(
          fichiers: _nouvellesPhotos,
          dossier: 'modeles_couture',
          onProgress: (p) => setState(() => _progressUpload = p),
        );
        photos.addAll(urls);
      } catch (e) {
        if (mounted) {
          setState(() => _enCours = false);
          _snack(Tr.s.erreurLorsEnvoiPhotos);
        }
        return;
      }
    }

    final modele = ModeleCouture(
      id: widget.modeleExistant?.id ?? ModeleCouture.collection.doc().id,
      couturierId: widget.couturierId,
      noms: {Langue.fr: nom},
      descriptions: {Langue.fr: _descCtrl.text.trim()},
      typeVetement: _type,
      mesuresRequises: _mesures.toList(),
      modesDisponibles: _modes.toList(),
      prixBase: PrixFCFA.arrondirAu50(prix),
      surDevis: _surDevis,
      delaiJours: int.tryParse(_delaiCtrl.text) ?? 3,
      photosExemples: photos,
      estActif: true,
      dateCreation: widget.modeleExistant?.dateCreation ?? DateTime.now(),
    );

    try {
      await ModeleCouture.collection
          .doc(modele.id)
          .set(modele.toMap(), SetOptions(merge: true));
      if (mounted) {
        _snack(widget.modeleExistant != null
            ? Tr.s.modeleMisJour
            : Tr.s.modelePublie);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _enCours = false);
        _snack(Tr.s.erreurLorsEnregistrement);
      }
    }
  }

  Widget _vignette(Widget image, {required VoidCallback onSupprimer}) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Stack(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(8), child: image),
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: onSupprimer,
                child: Container(
                  decoration: const BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ),
          ],
        ),
      );

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      );

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  String _typeLabel(TypeVetement t) => switch (t) {
        TypeVetement.boubou => Tr.s.boubou,
        TypeVetement.gandoura => Tr.s.gandoura,
        TypeVetement.robe => Tr.s.robe,
        TypeVetement.costume => Tr.s.costume,
        TypeVetement.chemise => Tr.s.chemise,
        TypeVetement.jupe => Tr.s.jupe,
        TypeVetement.pantalon => Tr.s.pantalon,
        TypeVetement.ensemble => Tr.s.ensemble,
        TypeVetement.autre => Tr.s.autre,
      };

  String _modeLabel(ModeRencontre m) => switch (m) {
        ModeRencontre.clientVientCouturier =>
          Tr.s.clientVientJePrendsSes,
        ModeRencontre.couturierVaClient => Tr.s.jeMeDeplaceChezClient,
        ModeRencontre.enLigne => Tr.s.clientSaisitSesMesuresLigne,
      };
}
