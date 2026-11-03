import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:sami/pages/mappage.dart';
import 'package:sami/l10n/tr.dart';

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
            title: Text(Tr.s.votrePosition),
            content: Text(
                Tr.s.pagneshopUtiliseVotrePositionUniquement),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(Tr.s.pasMaintenant)),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(Tr.s.continuer)),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(Tr.s.positionNonDisponible)));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(Tr.s.adresseLivraisonEnregistree),
          backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(Tr.s.erreurEnregistrement), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Tr.s.position),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (currentLocation != null)
              Text(
                Tr.s.latitudeLongitude(currentLocation!.latitude, currentLocation!.longitude),
                style: const TextStyle(fontSize: 20),
                textAlign: TextAlign.center,
              ),
            if (currentLocation == null)
              Text(
                Tr.s.attentePosition,
                style: TextStyle(fontSize: 20),
              ),
            ElevatedButton(
              onPressed:
                  navigateToMapPage, // Appeler la fonction pour naviguer vers MapPage
              child: Text(Tr.s.afficherSurCarte),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: (currentLocation == null || _enregistrement)
                  ? null : _enregistrerAdresse,
              icon: _enregistrement
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined),
              label: Text(Tr.s.enregistrerCommeAdresseLivraison),
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
