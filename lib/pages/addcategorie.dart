import 'package:sami/widgets/image_xfile.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sami/services/stockage_service.dart';
import 'package:sami/models/categorie.dart';

class AddCategoriePage extends StatefulWidget {
  const AddCategoriePage({super.key});

  @override
  _AddCategoriePageState createState() => _AddCategoriePageState();
}

class _AddCategoriePageState extends State<AddCategoriePage> {
  final TextEditingController _nomController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  XFile? _imageFile;
  String? _uploadedImageUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajouter une catégorie'),
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
                  : Container(
                      width: 100.0,
                      height: 100.0,
                      color: Colors.grey,
                    ),
              const SizedBox(height: 16.0),
              ElevatedButton(
                onPressed: () {
                  _addCategorie();
                },
                child: const Text('Ajouter'),
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

  Future<void> _addCategorie() async {
    String id = await Categorie.getNextId();
    String nom = _nomController.text;
    String description = _descriptionController.text;

    Categorie categorie = Categorie(
      id: id,
      nom: nom,
      description: description,
      image: _uploadedImageUrl ?? '',
    );

    // Upload image to Firebase Storage
    if (_imageFile != null) {
      try {
        final imageUrl = await StockageService.uploadXFile(
          fichier: _imageFile!,
          dossier: 'categories',
          nomFichier: '${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        _uploadedImageUrl = imageUrl;
        categorie = Categorie(
            id: id, nom: nom, description: description, image: imageUrl);
      } catch (e) {
        // Handle image upload error
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

    // Save categorie to Firestore
    try {
      await Categorie.categorieCollection.doc(id).set(categorie.toMap());
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Catégorie ajoutée'),
            content: const Text('La catégorie a été ajoutée avec succès.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop(); // Ferme la page d'ajout
                },
                child: const Text('Ok'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      // Handle Firestore error
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Erreur'),
            content: const Text(
                'Une erreur s\'est produite lors de l\'ajout de la catégorie. Veuillez réessayer.'),
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