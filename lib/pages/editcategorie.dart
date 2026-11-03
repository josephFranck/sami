import 'package:sami/widgets/image_xfile.dart';

import 'package:flutter/material.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sami/services/stockage_service.dart';
import 'package:sami/models/categorie.dart';

class EditCategoriePage extends StatefulWidget {
  final Categorie categorie;

  const EditCategoriePage({Key? key, required this.categorie}) : super(key: key);

  @override
  _EditCategoriePageState createState() => _EditCategoriePageState();
}

class _EditCategoriePageState extends State<EditCategoriePage> {
  late final TextEditingController _nomController;
  late final TextEditingController _descriptionController;
  XFile? _imageFile;
  String? _uploadedImageUrl;
  String? _initialImageUrl;

  @override
  void initState() {
    super.initState();
    _nomController = TextEditingController(text: widget.categorie.nom);
    _descriptionController =
        TextEditingController(text: widget.categorie.description);
    _initialImageUrl = widget.categorie.image;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modifier une catégorie'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nomController,
                decoration: const InputDecoration(labelText: 'Nom'),
              ),
              const SizedBox(height: 16.0),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
              ),
              const SizedBox(height: 16.0),
              ElevatedButton(
                onPressed: () {
                  _selectImage();
                },
                child: const Text('Sélectionner une image'),
              ),
              const SizedBox(height: 16.0),
              const Text('Image sélectionnée :'),
              const SizedBox(height: 8.0),
              _imageFile != null
                  ? ImageXFile(
                      _imageFile!,
                      width: 100.0,
                      height: 100.0,
                    )
                  : _initialImageUrl != null
                      ? ImageUniverselle(source: _initialImageUrl!,
                          width: 100.0,
                          height: 100.0,)
                      : Container(
                          width: 100.0,
                          height: 100.0,
                          color: Colors.grey,
                        ),
              const SizedBox(height: 16.0),
              ElevatedButton(
                onPressed: () {
                  _showConfirmationDialog();
                },
                child: const Text('Enregistrer les modifications'),
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
          title: const Text('Confirmer la modification'),
          content: const Text(
              'Êtes-vous sûr de vouloir enregistrer les modifications ?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirmer'),
            ),
          ],
        );
      },
    ).then((confirmed) {
      if (confirmed != null && confirmed) {
        _editCategorie();
      }
    });
  }

  Future<void> _editCategorie() async {
    String nom = _nomController.text;
    String description = _descriptionController.text;

    Categorie updatedCategorie = Categorie(
      id: widget.categorie.id,
      nom: nom,
      description: description,
      image: _uploadedImageUrl ?? _initialImageUrl ?? '',
    );

    if (_imageFile != null) {
      try {
        final imageUrl = await StockageService.uploadXFile(
          fichier: _imageFile!,
          dossier: 'categories',
          nomFichier: '${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        _uploadedImageUrl = imageUrl;
        updatedCategorie = Categorie(
            id: widget.categorie.id,
            nom: nom,
            description: description,
            image: imageUrl);
      } catch (e) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Erreur de chargement de l\'image'),
              content: const Text(
                  'Une erreur s\'est produite lors du chargement de l\'image. Veuillez réessayer.'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('Ok'),
                ),
              ],
            );
          },
        );
        return;
      }
    }

    try {
      await Categorie.categorieCollection
          .doc(widget.categorie.id)
          .update(updatedCategorie.toMap());

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Catégorie modifiée'),
            content: const Text('La catégorie a été modifiée avec succès.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop();
                },
                child: const Text('Ok'),
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
            title: const Text('Erreur'),
            content: const Text(
                'Une erreur s\'est produite lors de la modification de la catégorie. Veuillez réessayer.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Ok'),
              ),
            ],
          );
        },
      );
    }
  }
}