import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:sami/pages/mappage.dart';

class PositionPage extends StatefulWidget {
  const PositionPage({super.key});

  @override
  _PositionPageState createState() => _PositionPageState();
}

class _PositionPageState extends State<PositionPage> {
  Location location = Location();
  LocationData? currentLocation;

  double? latitude;
  double? longitude;

  @override
  void initState() {
    super.initState();
    initializeLocation();
  }

  void initializeLocation() async {
    bool serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        return;
      }
      location.onLocationChanged.listen((LocationData? locationData) {
        setState(() {
          currentLocation = locationData;
          latitude = locationData?.latitude;
          longitude = locationData?.longitude;
        });
      });
    }

    PermissionStatus permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      // INFORMATION PRÉALABLE (loi n° 2024/017) : dire POURQUOI avant de
      // demander — le système n'affiche que « autoriser / refuser ».
      if (mounted) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Votre position'),
            content: const Text(
                'PagneShop utilise votre position UNIQUEMENT pour placer le '
                'point de livraison sur la carte et guider le livreur. Elle '
                'n\'est ni suivie en continu ni partagée hors de votre '
                'commande. Vous pouvez aussi saisir votre adresse à la main.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Pas maintenant')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Continuer')),
            ],
          ),
        );
        if (ok != true) return;
      }
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        return;
      }
    }

    location.onLocationChanged.listen((LocationData? locationData) {
      setState(() {
        currentLocation = locationData;
        latitude = locationData?.latitude;
        longitude = locationData?.longitude;
      });
    });
  }

  void navigateToMapPage() {
    if (currentLocation != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MapPage(
            latitude: latitude!,
            longitude: longitude!,
          ),
        ),
      );
    }
  }

  bool _enregistrement = false;

  Future<void> _enregistrerAdresse() async {
    if (latitude == null || longitude == null) {
      // fallback sur currentLocation
      latitude = currentLocation?.latitude;
      longitude = currentLocation?.longitude;
    }
    if (latitude == null || longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Position non disponible')));
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Navigator.pushNamed(context, '/login');
      return;
    }
    setState(() => _enregistrement = true);
    try {
      await FirebaseFirestore.instance.collection('utilisateurs').doc(user.uid).update({
        'latitude': latitude,
        'longitude': longitude,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Adresse de livraison enregistrée'),
          backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Erreur d\'enregistrement'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Position'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (currentLocation != null)
              Text(
                'Latitude: ${currentLocation!.latitude}\nLongitude: ${currentLocation!.longitude}',
                style: const TextStyle(fontSize: 20),
                textAlign: TextAlign.center,
              ),
            if (currentLocation == null)
              const Text(
                'En attente de la position...',
                style: TextStyle(fontSize: 20),
              ),
            ElevatedButton(
              onPressed:
                  navigateToMapPage, // Appeler la fonction pour naviguer vers MapPage
              child: const Text('Afficher sur la carte'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: (currentLocation == null || _enregistrement)
                  ? null : _enregistrerAdresse,
              icon: _enregistrement
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined),
              label: const Text('Enregistrer comme adresse de livraison'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6A1B9A),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
