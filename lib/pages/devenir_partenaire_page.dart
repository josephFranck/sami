import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:location/location.dart';
import 'package:sami/services/candidature_service.dart';
import 'package:sami/services/stockage_service.dart';
import 'package:sami/l10n/tr.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kBg = Color(0xFFF7F5FA);

/// L'utilisateur candidate pour devenir boutiquier, couturier ou livreur.
/// L'admin valide ensuite (page Candidatures) : le rôle change et la fiche
/// métier est créée automatiquement.
class DevenirPartenairePage extends StatefulWidget {
  const DevenirPartenairePage({super.key});

  @override
  State<DevenirPartenairePage> createState() => _DevenirPartenairePageState();
}

class _DevenirPartenairePageState extends State<DevenirPartenairePage> {
  String? _type;
  final _c = <String, TextEditingController>{};
  bool _envoi = false;
  XFile? _pieceIdentite;   // photo CNI (livreur/couturier) ou justificatif boutique
  double? _lat, _lng;      // position de l'atelier/boutique (capturée sur place)

  TextEditingController _ctrl(String k) =>
      _c.putIfAbsent(k, () => TextEditingController());

  @override
  void dispose() {
    for (final ctrl in _c.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: Text(Tr.s.devenirPartenaire),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Suivi des candidatures existantes
          StreamBuilder<List<Candidature>>(
            stream: CandidatureService.streamMesCandidatures(),
            builder: (context, snap) {
              final list = snap.data ?? [];
              if (list.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Tr.s.mesCandidatures,
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  ...list.map((c) {
                    final (couleur, label) = switch (c.statut) {
                      'validee' => (Colors.green, 'Validée ✓'),
                      'refusee' => (Colors.red, 'Refusée'),
                      _ => (Colors.orange, 'En attente de validation'),
                    };
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        dense: true,
                        title: Text(_typeLabel(c.type)),
                        trailing: Text(label,
                            style: TextStyle(
                                color: couleur,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ),
                    );
                  }),
                  const Divider(height: 24),
                ],
              );
            },
          ),

          Text(Tr.s.jeVeuxDevenir,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          Row(
            children: [
              _choixRole('boutiquier', Icons.storefront, Tr.s.boutiquier),
              const SizedBox(width: 8),
              _choixRole('couturier', Icons.content_cut, Tr.s.couturier),
              const SizedBox(width: 8),
              _choixRole('livreur', Icons.delivery_dining, Tr.s.livreur),
            ],
          ),
          const SizedBox(height: 20),

          if (_type != null) ..._formulaire(),
        ],
      ),
    );
  }

  Widget _choixRole(String type, IconData icone, String label) {
    final sel = _type == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _type = type),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: sel ? _kPrimary : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: sel ? _kPrimary : Colors.grey.shade300),
          ),
          child: Column(
            children: [
              Icon(icone, color: sel ? Colors.white : _kPrimary, size: 26),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                      color: sel ? Colors.white : Colors.black87,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _formulaire() {
    final champs = switch (_type!) {
      'boutiquier' => [
          ('nomBoutique', 'Nom de la boutique'),
          ('quartier', 'Quartier'),
          ('telephone', 'Téléphone'),
          ('description', 'Description (types de pagnes vendus)'),
        ],
      'couturier' => [
          ('nom', 'Nom'),
          ('prenom', 'Prénom'),
          ('quartier', 'Quartier de l\'atelier'),
          ('telephone', 'Téléphone'),
        ],
      _ => [
          ('nom', 'Nom'),
          ('prenom', 'Prénom'),
          ('quartier', 'Quartier de base'),
          ('telephone', 'Téléphone'),
          ('numeroCNI', 'Numéro CNI'),
        ],
    };

    return [
      Text(Tr.s.dossier(_typeLabel(_type!)),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(height: 10),
      ...champs.map((ch) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: _ctrl(ch.$1),
              decoration: InputDecoration(
                labelText: ch.$2,
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          )),
      if (_type == 'livreur') ...[
        const SizedBox(height: 4),
        _menuVehicule(),
        const SizedBox(height: 10),
      ],
      // PIÈCE D'IDENTITÉ / JUSTIFICATIF (photo) — vérification du dossier
      const SizedBox(height: 4),
      Card(
        child: ListTile(
          dense: true,
          leading: Icon(
              _pieceIdentite != null
                  ? Icons.check_circle
                  : Icons.badge_outlined,
              color: _pieceIdentite != null ? Colors.green : _kPrimary),
          title: Text(
              _type == 'boutiquier'
                  ? Tr.s.photoCniGerantObligatoire
                  : Tr.s.photoVotreCniObligatoire,
              style: const TextStyle(fontSize: 13)),
          subtitle: Text(
              _pieceIdentite != null ? Tr.s.photoAjoutee : Tr.s.appuyezPourPhotographier,
              style: const TextStyle(fontSize: 11)),
          onTap: () async {
            final x = await ImagePicker()
                .pickImage(source: ImageSource.camera, imageQuality: 70);
            if (x != null) setState(() => _pieceIdentite = x);
          },
        ),
      ),
      // POSITION GPS (couturier/boutiquier) : capturée SUR PLACE, elle guide
      // les livreurs — indispensable pour les trajets.
      if (_type != 'livreur')
        Card(
          child: ListTile(
            dense: true,
            leading: Icon(
                _lat != null ? Icons.check_circle : Icons.my_location,
                color: _lat != null ? Colors.green : _kPrimary),
            title: Text(
                _type == 'couturier'
                    ? Tr.s.positionGpsAtelierObligatoire
                    : Tr.s.positionGpsBoutiqueObligatoire,
                style: const TextStyle(fontSize: 13)),
            subtitle: Text(
                _lat != null
                    ? Tr.s.positionCapturee
                    : Tr.s.soyezSurPlacePuisAppuyez,
                style: const TextStyle(fontSize: 11)),
            onTap: () async {
              try {
                final pos = await Location().getLocation();
                if (pos.latitude != null) {
                  setState(() {
                    _lat = pos.latitude;
                    _lng = pos.longitude;
                  });
                }
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(Tr.s.activezLocalisationReessayez)));
                }
              }
            },
          ),
        ),
      const SizedBox(height: 8),
      ElevatedButton(
        onPressed: _envoi ? null : _envoyer,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kPrimary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 48),
        ),
        child: _envoi
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : Text(Tr.s.envoyerMaCandidature),
      ),
      const SizedBox(height: 8),
      Text(
          Tr.s.administrateurExamineraVotreDossierVous,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          textAlign: TextAlign.center),
    ];
  }

  String _vehicule = 'moto';
  Widget _menuVehicule() => DropdownButtonFormField<String>(
        value: _vehicule,
        decoration: InputDecoration(
          labelText: Tr.s.typeVehicule,
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        items: [
          DropdownMenuItem(value: 'moto', child: Text(Tr.s.moto)),
          DropdownMenuItem(value: 'tricycle', child: Text(Tr.s.tricycle)),
          DropdownMenuItem(value: 'velo', child: Text(Tr.s.velo)),
          DropdownMenuItem(value: 'apied', child: Text(Tr.s.pied)),
        ],
        onChanged: (v) => setState(() => _vehicule = v ?? 'moto'),
      );

  Future<void> _envoyer() async {
    // Champs obligatoires minimaux
    final obligatoires = switch (_type!) {
      'boutiquier' => ['nomBoutique', 'quartier', 'telephone'],
      'couturier' => ['nom', 'prenom', 'quartier', 'telephone'],
      _ => ['nom', 'prenom', 'quartier', 'telephone', 'numeroCNI'],
    };
    for (final k in obligatoires) {
      if (_ctrl(k).text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(Tr.s.remplissezTousChamps)));
        return;
      }
    }

    if (_pieceIdentite == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(Tr.s.photoPieceIdentiteEstObligatoire)));
      return;
    }
    if (_type != 'livreur' && _lat == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(Tr.s.capturezPositionGpsSurPlace)));
      return;
    }

    setState(() => _envoi = true);
    try {
      // Upload de la pièce (base64 local pour l'instant, comme les images)
      final urlPiece = await StockageService.uploadXFile(
          fichier: _pieceIdentite!,
        dossier: 'pieces_candidatures',
      );
      final infos = {
        for (final e in _c.entries) e.key: e.value.text.trim(),
        if (_type == 'livreur') 'typeVehicule': _vehicule,
        'pieceIdentite': urlPiece,
        if (_lat != null) 'latitude': _lat,
        if (_lng != null) 'longitude': _lng,
      };
      await CandidatureService.deposer(type: _type!, infos: infos);
      if (mounted) {
        setState(() {
          _envoi = false;
          _type = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(Tr.s.candidatureEnvoyeeAttenteValidation),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _envoi = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  String _typeLabel(String t) => switch (t) {
        'boutiquier' => Tr.s.boutiquier,
        'couturier' => Tr.s.couturier,
        'livreur' => Tr.s.livreur,
        _ => t,
      };
}
