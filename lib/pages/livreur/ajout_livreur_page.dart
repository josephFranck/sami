import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/models/livreur.dart';

const _kPrimary = Color(0xFF6A1B9A);

/// Formulaire admin : créer une fiche livreur pour un utilisateur existant.
class AjoutLivreurPage extends StatefulWidget {
  const AjoutLivreurPage({super.key});

  @override
  State<AjoutLivreurPage> createState() => _AjoutLivreurPageState();
}

class _AjoutLivreurPageState extends State<AjoutLivreurPage> {
  final _nomCtrl = TextEditingController();
  final _prenomCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _quartierCtrl = TextEditingController();
  final _cniCtrl = TextEditingController();
  final _permisCtrl = TextEditingController();
  final _cautionCtrl = TextEditingController(text: '0');

  TypeVehicule _vehicule = TypeVehicule.moto;
  String? _utilisateurId; // utilisateur lié (rôle livreur)
  bool _enregistrement = false;

  @override
  void dispose() {
    for (final c in [
      _nomCtrl, _prenomCtrl, _telCtrl, _quartierCtrl,
      _cniCtrl, _permisCtrl, _cautionCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _enregistrer() async {
    if (_nomCtrl.text.trim().isEmpty ||
        _telCtrl.text.trim().isEmpty ||
        _cniCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Nom, téléphone et CNI sont obligatoires'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    setState(() => _enregistrement = true);
    try {
      final ref = Livreur.livreurCollection.doc(); // ID auto
      final livreur = Livreur(
        id: ref.id,
        utilisateurId: _utilisateurId ?? ref.id,
        nom: _nomCtrl.text.trim(),
        prenom: _prenomCtrl.text.trim(),
        telephone: _telCtrl.text.trim(),
        quartierBase: _quartierCtrl.text.trim().isEmpty
            ? 'Garoua'
            : _quartierCtrl.text.trim(),
        typeVehicule: _vehicule,
        numeroCNI: _cniCtrl.text.trim(),
        numeroPermis: _permisCtrl.text.trim(),
        cautionDeposee: double.tryParse(_cautionCtrl.text) ?? 0,
        estVerifie: true, // ajouté par l'admin → vérifié d'office
        dateInscription: DateTime.now(),
      );
      await ref.set(livreur.toMap());

      // Si un utilisateur est lié, lui attribuer le rôle livreur
      if (_utilisateurId != null) {
        await FirebaseFirestore.instance
            .collection('utilisateurs')
            .doc(_utilisateurId)
            .update({'role': 'livreur'});
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Livreur ajouté'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Erreur lors de l\'ajout'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajouter un livreur'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Lien avec un utilisateur existant (optionnel)
          _selecteurUtilisateur(),
          const SizedBox(height: 16),
          _champ(_prenomCtrl, 'Prénom'),
          _champ(_nomCtrl, 'Nom *'),
          _champ(_telCtrl, 'Téléphone *', clavier: TextInputType.phone),
          _champ(_quartierCtrl, 'Quartier de base', hint: 'ex: Plateau'),
          _champ(_cniCtrl, 'Numéro CNI *'),
          _champ(_permisCtrl, 'Numéro de permis (optionnel)'),
          const SizedBox(height: 8),
          _selecteurVehicule(),
          const SizedBox(height: 8),
          _champ(_cautionCtrl, 'Caution déposée (FCFA)',
              clavier: TextInputType.number),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _enregistrement ? null : _enregistrer,
              icon: _enregistrement
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.person_add),
              label: const Text('Enregistrer le livreur'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Sélecteur d'utilisateur existant (rôle client/livreur) à promouvoir
  Widget _selecteurUtilisateur() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kPrimary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Lier à un compte existant (optionnel)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('utilisateurs')
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Text('Chargement...',
                    style: TextStyle(fontSize: 12, color: Colors.grey));
              }
              final users = snap.data!.docs;
              return DropdownButton<String?>(
                value: _utilisateurId,
                isExpanded: true,
                hint: const Text('Aucun (créer une fiche indépendante)'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Aucun (fiche indépendante)'),
                  ),
                  ...users.map((d) {
                    final data = d.data();
                    final nom =
                        '${data['prenom'] ?? ''} ${data['nom'] ?? ''}'.trim();
                    final tel = data['telephone'] ?? '';
                    return DropdownMenuItem<String?>(
                      value: d.id,
                      child: Text(
                          '${nom.isEmpty ? 'Sans nom' : nom} · $tel',
                          overflow: TextOverflow.ellipsis),
                    );
                  }),
                ],
                onChanged: (v) {
                  setState(() {
                    _utilisateurId = v;
                    // Pré-remplir depuis le compte choisi
                    if (v != null) {
                      final doc = users.firstWhere((d) => d.id == v);
                      final data = doc.data();
                      _nomCtrl.text = data['nom'] ?? '';
                      _prenomCtrl.text = data['prenom'] ?? '';
                      _telCtrl.text = data['telephone'] ?? '';
                      _quartierCtrl.text = data['quartier'] ?? '';
                    }
                  });
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _selecteurVehicule() {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Type de véhicule',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<TypeVehicule>(
          value: _vehicule,
          isExpanded: true,
          items: TypeVehicule.values
              .map((v) => DropdownMenuItem(
                    value: v,
                    child: Text(_labelVehicule(v)),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _vehicule = v!),
        ),
      ),
    );
  }

  String _labelVehicule(TypeVehicule v) => switch (v) {
        TypeVehicule.moto => 'Moto',
        TypeVehicule.tricycle => 'Tricycle',
        TypeVehicule.velo => 'Vélo',
        TypeVehicule.apied => 'À pied',
      };

  Widget _champ(TextEditingController ctrl, String label,
      {String? hint, TextInputType? clavier}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: ctrl,
        keyboardType: clavier,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}
