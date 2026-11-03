import 'dart:io';
import 'package:sami/widgets/image_xfile.dart';

import 'package:flutter/material.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sami/services/stockage_service.dart';
import 'package:sami/l10n/tr.dart';
import 'package:sami/models/pagne.dart'; // Importez le modèle Pagne

class EditPagnePage extends StatefulWidget {
  final Pagne pagne;

  const EditPagnePage({Key? key, required this.pagne}) : super(key: key);

  @override
  _EditPagnePageState createState() => _EditPagnePageState();
}

class _EditPagnePageState extends State<EditPagnePage> {
  late final TextEditingController _nomController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _prixController;
  late final TextEditingController _matiereController;
  late final TextEditingController _createurController;
  late final TextEditingController _origineController;
  late final TextEditingController _delaiController;
  late final TextEditingController _quantiteController;
  late final TextEditingController _stockController;
  late final TextEditingController _coutAchatController;
  late final TextEditingController _videoController;

  List<String> _uploadedImageUrls = [];
  List<String> _initialImageUrls = []; // Stocker les URLs initiales des images
  List<String> _categories = [];
  List<String> _tailles = [];
  List<String> _couleurs = [];
  List<String> _promotions = [];
  List<String> _tags = [];
  Map<String, String> _commentaires = {};

  @override
  void initState() {
    super.initState();
    _nomController = TextEditingController(text: widget.pagne.nom);
    _descriptionController = TextEditingController(text: widget.pagne.description);
    _prixController = TextEditingController(text: widget.pagne.prixParBoutique.toString());
    _matiereController = TextEditingController(text: widget.pagne.matiere);
    _createurController = TextEditingController(text: widget.pagne.createur);
    _origineController = TextEditingController(text: widget.pagne.origine);
    _delaiController = TextEditingController(text: widget.pagne.delaiLivraison.toString());
    _quantiteController = TextEditingController(text: widget.pagne.quantiteMinCommande.toString());
    _stockController = TextEditingController(text: widget.pagne.quantiteStock.toString());
    _coutAchatController = TextEditingController(text: (widget.pagne.coutAchat ?? 0).toStringAsFixed(0));
    _videoController = TextEditingController(text: widget.pagne.videoPresentation);

    _initialImageUrls = List.from(widget.pagne.images); // Initialisation des URLs initiales
    _categories = List.from(widget.pagne.categories); // Initialisation
    _tailles = List.from(widget.pagne.tailles); // Initialisation
    _couleurs = List.from(widget.pagne.couleurs); // Initialisation
    // _promotions = List.from(widget.pagne.promotions); // Initialisation
    _tags = List.from(widget.pagne.tags); // Initialisation
    _commentaires = Map.from(widget.pagne.commentaires); // Initialisation
    // _gerants = List.from(widget.pagne.gerants); // Initialisation

  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Tr.s.modifierPagne),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nomController,
                decoration: InputDecoration(labelText: Tr.s.nom),
              ),
              const SizedBox(height: 16.0),
              TextField(
                controller: _descriptionController,
                decoration: InputDecoration(labelText: Tr.s.description),
                maxLines: 3,
              ),
              const SizedBox(height: 16.0),
              TextField(
                controller: _prixController,
                decoration: InputDecoration(labelText: Tr.s.prix),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16.0),
              TextField(
                controller: _matiereController,
                decoration: InputDecoration(labelText: Tr.s.matiere),
              ),
              const SizedBox(height: 16.0),
              TextField(
                controller: _createurController,
                decoration: InputDecoration(labelText: Tr.s.createur),
              ),
              const SizedBox(height: 16.0),
              TextField(
                controller: _origineController,
                decoration: InputDecoration(labelText: Tr.s.origine),
              ),
              const SizedBox(height: 16.0),
              TextField(
                controller: _delaiController,
                decoration: InputDecoration(labelText: Tr.s.delaiLivraisonJours),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16.0),
              TextField(
                controller: _quantiteController,
                decoration: InputDecoration(labelText: Tr.s.quantiteMinimaleCommande),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16.0),
              TextField(
                controller: _stockController,
                decoration: InputDecoration(labelText: Tr.s.stockDisponible),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16.0),
              TextField(
                controller: _coutAchatController,
                decoration: InputDecoration(
                  labelText: Tr.s.coutAchatFcfa,
                  helperText: Tr.s.sertCalculPrixVotreMarge,
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16.0),
              TextField(
                controller: _videoController,
                decoration: InputDecoration(labelText: Tr.s.lienVideoPresentation),
              ),
              const SizedBox(height: 16.0),
              ElevatedButton(
                onPressed: () {
                  _selectImages();
                },
                child: Text(Tr.s.selectionnerImages),
              ),
              const SizedBox(height: 16.0),
              Text(Tr.s.imagesSelectionnees),
              const SizedBox(height: 8.0),
              _buildImagePreview(),
              const SizedBox(height: 16.0),
              ElevatedButton(
                onPressed: () {
                  _showConfirmationDialog();
                },
                child: Text(Tr.s.enregistrerModifications),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<XFile> _imageFiles = [];

  void _selectImages() async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage();

    if (mounted) setState(() {
      if (pickedFiles != null) {
        _imageFiles.addAll(pickedFiles);
      }
    });
  }

  Widget _buildImagePreview() {
    if (_imageFiles.isEmpty && _initialImageUrls.isNotEmpty) {
      return Wrap(
        children: _initialImageUrls.map((imageUrl) => Padding(
          padding: const EdgeInsets.all(8.0),
          child: ImageUniverselle(source: imageUrl,
            width: 100.0,
            height: 100.0,
            fit: BoxFit.cover,),
        )).toList(),
      );
    } else {
      return Wrap(
        children: _imageFiles.map((imageFile) => Padding(
          padding: const EdgeInsets.all(8.0),
          child: ImageXFile(imageFile,
            width: 100.0,
            height: 100.0,
            fit: BoxFit.cover,
          ),
        )).toList(),
      );
    }
  }


  void _showConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(Tr.s.confirmerModification),
          content: Text(
              Tr.s.etesVousSurVouloirEnregistrer),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(Tr.s.annuler),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(Tr.s.confirmer),
            ),
          ],
        );
      },
    ).then((confirmed) {
      if (confirmed != null && confirmed) {
        _editPagne();
      }
    });
  }

  Future<void> _editPagne() async {
    String nom = _nomController.text;
    String description = _descriptionController.text;
    double prix = double.tryParse(_prixController.text) ?? 0.0;
    String matiere = _matiereController.text;
    String createur = _createurController.text;
    String origine = _origineController.text;
    int delai = int.tryParse(_delaiController.text) ?? 0;
    int quantite = int.tryParse(_quantiteController.text) ?? 0;
    String video = _videoController.text;

    List<String> updatedImageUrls = List.from(_initialImageUrls); // Start with existing URLs

    // Upload new images and add their URLs
    if (_imageFiles.isNotEmpty) {
      try {
        for (final imageFile in _imageFiles) {
          final imageUrl = await StockageService.uploadXFile(
          fichier: imageFile,
          dossier: 'pagnes',
          nomFichier: '${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
          updatedImageUrls.add(imageUrl);
        }
      } catch (e) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text(Tr.s.erreurChargementImages),
              content: Text(
                  Tr.s.erreurSEstProduiteLors4),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text(Tr.s.ok),
                ),
              ],
            );
          },
        );
        return;
      }
    }

    Pagne updatedPagne = Pagne(
      id: widget.pagne.id,
      nom: nom,
      description: description,
      prixParBoutique: prix,
      images: updatedImageUrls,
      categories: _categories,
      tailles: _tailles,
      couleurs: _couleurs,
      matiere: matiere,
      createur: createur,
      // promotions: _promotions,
      tags: _tags,
      commentaires: _commentaires,
      noteMoyenne: widget.pagne.noteMoyenne, // Keep the existing average rating
      mention: widget.pagne.mention,       // Keep the existing mention
      origine: origine,
      disponible: (int.tryParse(_stockController.text) ?? 0) > 0,
      prixDeGros: widget.pagne.prixDeGros,
      quantiteMinCommande: quantite,
      quantiteStock: int.tryParse(_stockController.text) ?? widget.pagne.quantiteStock,
      quantiteDisponible: int.tryParse(_stockController.text) ?? widget.pagne.quantiteDisponible,
      quantiteReservee: widget.pagne.quantiteReservee,
      coutAchat: double.tryParse(_coutAchatController.text) ?? widget.pagne.coutAchat,
      beneficeSouhaite: widget.pagne.beneficeSouhaite,
      boutiqueId: widget.pagne.boutiqueId,
      nomArtisan: widget.pagne.nomArtisan,
      dateAjout: widget.pagne.dateAjout,
      delaiLivraison: delai,
      videoPresentation: video,
    );

    try {
      await Pagne.pagneCollection.doc(widget.pagne.id).update(updatedPagne.toMap());

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(Tr.s.pagneModifie),
            content: Text(Tr.s.pagneEteModifieAvecSucces),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop();
                },
                child: Text(Tr.s.ok),
              ),
            ],
          );
        },
      );
    } catch (e) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(Tr.s.erreur),
            content: Text(
                Tr.s.erreurSEstProduiteLors5),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text(Tr.s.ok),
              ),
            ],
          );
        },
      );
    }
  }
}