import 'package:firebase_auth/firebase_auth.dart';
import 'package:sami/widgets/image_xfile.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:location/location.dart';
import 'package:sami/services/stockage_service.dart';
import 'package:sami/models/boutique.dart'; // Importez le modèle Boutique

class AddBoutiquePage extends StatefulWidget {
  const AddBoutiquePage({super.key});

  @override
  _AddBoutiquePageState createState() => _AddBoutiquePageState();
}

class _AddBoutiquePageState extends State<AddBoutiquePage> {
  // La création DIRECTE de boutique est un outil ADMIN/STAFF.
  // Le parcours boutiquier = candidature « Devenir partenaire » :
  // c'est la validation qui crée la boutique (KYC, pièce, GPS).
  bool _accesVerifie = false;
  bool _accesAutorise = false;

  Future<void> _verifierAcces() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u != null) {
      final me = await FirebaseFirestore.instance
          .collection('utilisateurs').doc(u.uid).get();
      final role = me.data()?['role'] as String?;
      _accesAutorise = role == 'admin' || role == 'agent';
    }
    if (mounted) setState(() => _accesVerifie = true);
  }

  final TextEditingController _nomController = TextEditingController();
  final TextEditingController _adresseController = TextEditingController();
  final TextEditingController _telephoneController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  XFile? _imageFile;
  String? _uploadedImageUrl;
  List<String> _methodesPaiement = []; // Liste pour les méthodes de paiement
  List<String> _gerants = []; // Liste pour les gérants (IDs utilisateurs)
  List<String> _allUserIds = []; // Stocke tous les IDs utilisateur
  Map<String, String> _userNames = {}; // Stocke les noms d'utilisateur (ID -> Nom)
  bool _isLoadingUsers = true; // Indique si les utilisateurs sont en cours de chargement
  double? _latitude;
  double? _longitude;
  bool _captureGpsEnCours = false;

  @override
  void initState() {
    super.initState();
    _verifierAcces();
    _loadUsers(); // Charge les utilisateurs au démarrage
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoadingUsers = true;
    });

    try {
      final QuerySnapshot usersSnapshot =
          await FirebaseFirestore.instance.collection('utilisateurs').get(); // Remplacez 'users' par le nom de votre collection d'utilisateurs

      _allUserIds = usersSnapshot.docs.map((doc) => doc.id).toList();

      // Récupérer les noms d'utilisateur (plus efficace avec un seul appel)
      for (final doc in usersSnapshot.docs) {
        _userNames[doc.id] = doc['nom'] as String? ?? ''; // Assurez-vous que le champ 'nom' existe dans votre collection d'utilisateurs
      }

    } catch (e) {
      print("Erreur lors du chargement des utilisateurs: $e");
      // Gérez l'erreur comme vous le souhaitez (par exemple, affichez un message à l'utilisateur)
    } finally {
      setState(() {
        _isLoadingUsers = false;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    if (!_accesVerifie) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_accesAutorise) {
      return Scaffold(
        appBar: AppBar(title: const Text('Créer une boutique')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.storefront_outlined, size: 56, color: Colors.grey),
              const SizedBox(height: 12),
              const Text(
                'Pour ouvrir votre boutique sur SAMI, déposez une candidature « Devenir partenaire » : c\'est sa validation qui crée votre boutique (vérification d\'identité et localisation incluses).',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => Navigator.pushReplacementNamed(
                    context, '/devenir-partenaire'),
                icon: const Icon(Icons.how_to_reg_outlined),
                label: const Text('Devenir partenaire'),
              ),
            ]),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajouter une boutique'),
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
                controller: _adresseController,
                decoration: const InputDecoration(labelText: 'Adresse'),
              ),
              const SizedBox(height: 16.0),
              // Bouton de capture GPS de la boutique
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _captureGpsEnCours ? null : _capturerPosition,
                icon: _captureGpsEnCours
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(_latitude != null ? Icons.check_circle : Icons.my_location,
                        color: _latitude != null ? Colors.green : null),
                label: Text(_latitude != null
                    ? 'Position enregistrée ✓'
                    : 'Capturer la position GPS de la boutique'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _telephoneController,
                decoration: const InputDecoration(labelText: 'Téléphone'),
                keyboardType: TextInputType.phone, // Clavier numérique
              ),
              const SizedBox(height: 16.0),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
              ),
              const SizedBox(height: 16.0),
              const Text("Gérants :"),
              _isLoadingUsers
                  ? const CircularProgressIndicator() // Afficher un indicateur de chargement
                  : _buildGerantDropdown(), // Liste déroulante des gérants

              const SizedBox(height: 16.0),
              // Sélection des méthodes de paiement (exemple avec CheckboxListTile)
              const Text("Méthodes de paiement :"),
              CheckboxListTile(
                title: const Text("Carte de crédit"),
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
                title: const Text("Espèces"),
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
              // ... Ajoutez d'autres CheckboxListTile pour les autres méthodes

              const SizedBox(height: 16.0),

              ElevatedButton(
                onPressed: () {
                  _selectImage();
                },
                child: const Text('Sélectionner un logo'),
              ),
              const SizedBox(height: 16.0),
              const Text('Logo sélectionné :'),
              const SizedBox(height: 8.0),
              _imageFile != null
                  ? ImageXFile(
                      _imageFile!,
                      width: 100.0,
                      height: 100.0,
                      fit: BoxFit.cover, // Pour que l'image ne se déforme pas
                    )
                  : Container(
                      width: 100.0,
                      height: 100.0,
                      color: Colors.grey,
                      child: const Icon(Icons.image, color: Colors.white), // Icône par défaut
                    ),
              const SizedBox(height: 16.0),
              ElevatedButton(
                onPressed: () {
                  _addBoutique();
                },
                child: const Text('Ajouter'),
              ),
            ],
          ),
        ),
      ),
    );
  }

   Widget _buildGerantDropdown() {
    final TextEditingController _controller = TextEditingController();
    return Autocomplete<String>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return _userNames.values; // Afficher tous les noms si le champ est vide
        }
        return _userNames.values.where((String option) {
          return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
        });
      },
      onSelected: (String selection) {
        final selectedUserId = _userNames.keys.firstWhere((k) => _userNames[k] == selection);
        setState(() {
          if (_gerants.contains(selectedUserId)) {
            _gerants.remove(selectedUserId);
          } else {
            _gerants.add(selectedUserId);
          }
          _controller.clear(); // Effacer le texte après la sélection
        });
      },
      displayStringForOption: (String option) => option, // Afficher le nom
      fieldViewBuilder: (BuildContext context,
          TextEditingController textEditingController,
          FocusNode focusNode,
          VoidCallback onFieldSubmitted) {
        return Wrap(
          children: [
            TextField(
              controller: textEditingController,
              focusNode: focusNode,
              onEditingComplete: () {
                onFieldSubmitted();
              },
              decoration: InputDecoration(
                hintText: 'Rechercher un gérant',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _controller.clear();
                  },
                ),
              ),
              
            ),
            // Afficher les gérants sélectionnés
            ..._gerants.map((userId) => Chip(
              label: Text(_userNames[userId]!),
              onDeleted: () {
                setState(() {
                  _gerants.remove(userId);
                });
              },
            )),
          ],
        );
      },
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

  Future<void> _capturerPosition() async {
    setState(() => _captureGpsEnCours = true);
    try {
      final location = Location();
      bool serviceActif = await location.serviceEnabled();
      if (!serviceActif) serviceActif = await location.requestService();
      if (!serviceActif) { setState(() => _captureGpsEnCours = false); return; }

      var permission = await location.hasPermission();
      if (permission == PermissionStatus.denied) {
        permission = await location.requestPermission();
      }
      if (permission != PermissionStatus.granted) {
        setState(() => _captureGpsEnCours = false);
        return;
      }

      final pos = await location.getLocation();
      if (mounted) setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
        _captureGpsEnCours = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Position de la boutique enregistrée'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      setState(() => _captureGpsEnCours = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Impossible de capter la position'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _addBoutique() async {
    String id = await Boutique.getNextId();
    String nom = _nomController.text;
    String adresse = _adresseController.text;
    String telephone = _telephoneController.text;
    String description = _descriptionController.text;

    Boutique boutique = Boutique(
      id: id,
      nom: nom,
      adresse: adresse,
      telephone: telephone,
      description: description,
      logo: _uploadedImageUrl ?? '',
      methodesPaiement: _methodesPaiement,
      gerants: _gerants,
      latitude: _latitude,
      longitude: _longitude,
    );

    // Upload image to Firebase Storage (si une image a été sélectionnée)
    if (_imageFile != null) {
      try {
        final imageUrl = await StockageService.uploadXFile(
          fichier: _imageFile!,
          dossier: 'boutiques',
          nomFichier: '${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        _uploadedImageUrl = imageUrl;
        boutique = Boutique(
          id: id,
          nom: nom,
          adresse: adresse,
          telephone: telephone,
          description: description,
          logo: imageUrl,
          methodesPaiement: _methodesPaiement,
          gerants: _gerants,
          latitude: _latitude,
          longitude: _longitude,
        );
      } catch (e) {
        // Gestion de l'erreur de chargement de l'image
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Erreur de chargement du logo'),
              content: const Text(
                  'Une erreur s\'est produite lors du chargement du logo. Veuillez réessayer.'),
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
        return; // Important : sortir de la fonction en cas d'erreur d'image
      }
    }

    // Enregistrement de la boutique dans Firestore
    try {
      await Boutique.boutiqueCollection.doc(id).set(boutique.toMap());
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Boutique ajoutée'),
            content: const Text('La boutique a été ajoutée avec succès.'),
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
      // Gestion de l'erreur Firestore
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Erreur'),
            content: const Text(
                'Une erreur s\'est produite lors de l\'ajout de la boutique. Veuillez réessayer.'),
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