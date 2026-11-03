import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sami/widgets/image_xfile.dart';

import 'package:flutter/material.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sami/services/stockage_service.dart';
import 'package:sami/l10n/tr.dart';
import 'package:sami/models/boutique.dart'; // Importez le modèle Boutique

class EditBoutiquePage extends StatefulWidget {
  final Boutique boutique;

  const EditBoutiquePage({Key? key, required this.boutique}) : super(key: key);

  @override
  _EditBoutiquePageState createState() => _EditBoutiquePageState();
}

class _EditBoutiquePageState extends State<EditBoutiquePage> {
  late final TextEditingController _nomController;
  late final TextEditingController _adresseController;
  late final TextEditingController _telephoneController;
  late final TextEditingController _descriptionController;
  XFile? _imageFile;
  String? _uploadedImageUrl;
  String? _initialImageUrl;
  List<String> _methodesPaiement = [];
  List<String> _gerants = [];


  @override
  void initState() {
    super.initState();
    _nomController = TextEditingController(text: widget.boutique.nom);
    _adresseController = TextEditingController(text: widget.boutique.adresse);
    _telephoneController = TextEditingController(text: widget.boutique.telephone);
    _descriptionController =
        TextEditingController(text: widget.boutique.description);
    _initialImageUrl = widget.boutique.logo;
    _methodesPaiement = List.from(widget.boutique.methodesPaiement); // Initialisation
    _gerants = List.from(widget.boutique.gerants); // Initialisation
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Tr.s.modifierBoutique),
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
                controller: _adresseController,
                decoration: InputDecoration(labelText: Tr.s.adresse),
              ),
              const SizedBox(height: 16.0),
              TextField(
                controller: _telephoneController,
                decoration: InputDecoration(labelText: Tr.s.telephone),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16.0),
              TextField(
                controller: _descriptionController,
                decoration: InputDecoration(labelText: Tr.s.description),
                maxLines: 3,
              ),
              const SizedBox(height: 16.0),

              Text(Tr.s.methodesPaiement),
              CheckboxListTile(
                title: Text(Tr.s.carteCredit),
                value: _methodesPaiement.contains("carte"),
                onChanged: (bool? value) {
                  setState(() {
                    if (value!) {
                      _methodesPaiement.add("carte");
                    } else {
                      _methodesPaiement.remove("carte");
                    }
                  });
                },
              ),
              CheckboxListTile(
                title: Text(Tr.s.especes),
                value: _methodesPaiement.contains("especes"),
                onChanged: (bool? value) {
                  setState(() {
                    if (value!) {
                      _methodesPaiement.add("especes");
                    } else {
                      _methodesPaiement.remove("especes");
                    }
                  });
                },
              ),
              // ... autres méthodes de paiement

              const SizedBox(height: 16.0),

              ElevatedButton(
                onPressed: () {
                  _selectImage();
                },
                child: Text(Tr.s.selectionnerLogo),
              ),
              const SizedBox(height: 16.0),
              Text(Tr.s.logoSelectionne),
              const SizedBox(height: 8.0),
              _imageFile != null
                  ? ImageXFile(
                      _imageFile!,
                      width: 100.0,
                      height: 100.0,
                      fit: BoxFit.cover,
                    )
                  : _initialImageUrl != null
                      ? ImageUniverselle(source: _initialImageUrl!,
                          width: 100.0,
                          height: 100.0,
                          fit: BoxFit.cover,)
                      : Container(
                          width: 100.0,
                          height: 100.0,
                          color: Colors.grey,
                          child: const Icon(Icons.image, color: Colors.white),
                        ),
              const SizedBox(height: 16.0),
              ElevatedButton(
                onPressed: () {
                  _showConfirmationDialog();
                },
                child: Text(Tr.s.enregistrerModifications),
              ),
              SwitchListTile(
                title: Text(Tr.s.retraitBoutique,
                    style: TextStyle(fontSize: 14)),
                subtitle: Text(
                    Tr.s.vosClientsPeuventVenirChercher,
                    style: TextStyle(fontSize: 11.5)),
                value: widget.boutique.retraitEnBoutique,
                activeColor: Colors.green,
                onChanged: (v) async {
                  await FirebaseFirestore.instance
                      .collection('boutiques')
                      .doc(widget.boutique.id)
                      .update({'retraitEnBoutique': v});
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              const Divider(height: 30),
              // CYCLE DE VIE : on ne SUPPRIME pas une boutique (commandes,
              // reçus et comptabilité y sont liés) — on la DÉSACTIVE :
              // masquée du catalogue, réactivable à tout moment.
              SwitchListTile(
                title: Text(Tr.s.boutiqueActiveVisibleClients,
                    style: TextStyle(fontSize: 14)),
                subtitle: Text(
                    Tr.s.desactiverMasqueBoutiqueMetTous,
                    style: TextStyle(fontSize: 11.5)),
                value: widget.boutique.estActif,
                activeColor: Colors.green,
                onChanged: (v) async {
                  final db = FirebaseFirestore.instance;
                  await db
                      .collection('boutiques')
                      .doc(widget.boutique.id)
                      .update({'estActif': v});
                  if (!v) {
                    // cascade : retirer ses pagnes du catalogue
                    final ps = await db
                        .collection('pagnes')
                        .where('boutiqueId', isEqualTo: widget.boutique.id)
                        .get();
                    final batch = db.batch();
                    for (final d in ps.docs) {
                      batch.update(d.reference, {'disponible': false});
                    }
                    await batch.commit();
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(v
                            ? Tr.s.boutiqueReactiveeRemettezVosPagnes
                            : Tr.s.boutiqueDesactiveePagnesRetiresCatalogue),
                        backgroundColor: v ? Colors.green : Colors.orange));
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectImage() async {
    final picker = ImagePicker();
    final pickedImage = await picker.pickImage(source: ImageSource.gallery);

    if (mounted) setState(() {
      if (pickedImage != null) {
        _imageFile = pickedImage;
      }
    });
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
        _editBoutique();
      }
    });
  }

  Future<void> _editBoutique() async {
    String nom = _nomController.text;
    String adresse = _adresseController.text;
    String telephone = _telephoneController.text;
    String description = _descriptionController.text;

    Boutique updatedBoutique = Boutique(
      id: widget.boutique.id,
      nom: nom,
      adresse: adresse,
      telephone: telephone,
      description: description,
      logo: _uploadedImageUrl ?? _initialImageUrl ?? '',
      methodesPaiement: _methodesPaiement,
      gerants: _gerants,
      // Préserver les champs non édités (sinon perdus à chaque modification)
      latitude: widget.boutique.latitude,
      longitude: widget.boutique.longitude,
      ville: widget.boutique.ville,
      quartier: widget.boutique.quartier,
      billingModel: widget.boutique.billingModel,
      estActif: widget.boutique.estActif,
      dateInscription: widget.boutique.dateInscription,
    );

    if (_imageFile != null) {
      try {
        final imageUrl = await StockageService.uploadXFile(
          fichier: _imageFile!,
          dossier: 'boutiques',
          nomFichier: '${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        _uploadedImageUrl = imageUrl;
        updatedBoutique = Boutique(
          id: widget.boutique.id,
          nom: nom,
          adresse: adresse,
          telephone: telephone,
          description: description,
          logo: imageUrl,
          methodesPaiement: _methodesPaiement,
          gerants: _gerants,
          latitude: widget.boutique.latitude,
          longitude: widget.boutique.longitude,
          ville: widget.boutique.ville,
          quartier: widget.boutique.quartier,
          billingModel: widget.boutique.billingModel,
          estActif: widget.boutique.estActif,
          dateInscription: widget.boutique.dateInscription,
        );
      } catch (e) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text(Tr.s.erreurChargementLogo),
              content: Text(
                  Tr.s.erreurSEstProduiteLors),
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

    try {
      await Boutique.boutiqueCollection
          .doc(widget.boutique.id)
          .update(updatedBoutique.toMap());

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(Tr.s.boutiqueModifiee),
            content: Text(Tr.s.boutiqueEteModifieeAvecSucces),
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
                Tr.s.erreurSEstProduiteLors3),
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