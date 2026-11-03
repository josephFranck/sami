import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sami/models/utilisateur.dart';
import 'package:sami/pages/legal/mentions_legales_page.dart';
import 'package:sami/services/langue_service.dart';
import 'package:sami/services/parrainage_service.dart';
import 'package:uuid/uuid.dart';
import 'package:sami/l10n/tr.dart';

const _kPrimary = Color(0xFF6A1B9A);

/// COMPLÉTER MON PROFIL — affiché par _AuthGate quand un compte connecté
/// (téléphone, WhatsApp, Telegram, Facebook… ou ancien compte) n'a pas
/// encore de fiche `utilisateurs` complète avec consentement aux CGU
/// (preuve du consentement : art. 26 loi 2010/021 ; loi 2024/017).
class CompleterProfilPage extends StatefulWidget {
  final Map<String, dynamic>? existant; // doc partiel éventuel
  const CompleterProfilPage({super.key, this.existant});

  @override
  State<CompleterProfilPage> createState() => _CompleterProfilPageState();
}

class _CompleterProfilPageState extends State<CompleterProfilPage> {
  final _formKey = GlobalKey<FormState>();
  late final _nomCtrl = TextEditingController(text: widget.existant?['nom'] as String? ?? '');
  late final _prenomCtrl = TextEditingController(text: widget.existant?['prenom'] as String? ?? '');
  late final _quartierCtrl = TextEditingController(text: widget.existant?['quartier'] as String? ?? '');
  late final _villeCtrl = TextEditingController(text: widget.existant?['ville'] as String? ?? 'Garoua');
  late final _emailCtrl = TextEditingController(text: widget.existant?['email'] as String? ?? (FirebaseAuth.instance.currentUser?.email ?? ''));
  final _parrainageCtrl = TextEditingController();
  bool _accepteCgu = false;
  bool _majeur = false;
  bool _consentMarketing = false;
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    for (final c in [_nomCtrl, _prenomCtrl, _quartierCtrl, _villeCtrl, _emailCtrl, _parrainageCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _valider() async {
    setState(() => _erreur = null);
    if (!_formKey.currentState!.validate()) return;
    if (!_accepteCgu || !_majeur) {
      setState(() => _erreur = !_accepteCgu
          ? Tr.s.vousDevezAccepterConditionsGenerales2
          : Tr.s.serviceEstReservePersonnesMajeures);
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _enCours = true);
    try {
      final ref = FirebaseFirestore.instance.collection('utilisateurs').doc(user.uid);
      final existe = widget.existant != null;
      final tel = widget.existant?['telephone'] as String? ?? user.phoneNumber ?? '';
      if (!existe) {
        final codeParrainage =
            'SAMI-${_nomCtrl.text.toUpperCase().substring(0, min(6, _nomCtrl.text.length))}-${const Uuid().v4().substring(0, 4).toUpperCase()}';
        final u = Utilisateur(
          id: user.uid,
          image: user.photoURL ?? '',
          nom: _nomCtrl.text.trim(),
          prenom: _prenomCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          adresse: '${_quartierCtrl.text}, ${_villeCtrl.text}',
          telephone: tel,
          dateInscription: DateTime.now(),
          derniereConnexion: DateTime.now(),
          estVerifie: user.phoneNumber != null,
          estActif: true,
          role: 'client',
          historiqueCommandes: [],
          panier: [],
          favoris: [],
          methodesPaiement: [],
          adresseLivraison: ['${_quartierCtrl.text}, ${_villeCtrl.text}, Cameroun'],
          langue: LangueService.instance.langue,
          notifications: true,
          quartier: _quartierCtrl.text.trim(),
          ville: _villeCtrl.text.trim(),
          pays: 'Cameroun',
          niveau: 1,
          pointsFidelite: 0,
          creditBalance: 0,
          codeParrainage: codeParrainage,
        );
        await ref.set(u.toMap());
      } else {
        await ref.set({
          'nom': _nomCtrl.text.trim(),
          'prenom': _prenomCtrl.text.trim(),
          'quartier': _quartierCtrl.text.trim(),
          'ville': _villeCtrl.text.trim(),
          if (_emailCtrl.text.trim().isNotEmpty) 'email': _emailCtrl.text.trim(),
          'langue': LangueService.instance.langue,
        }, SetOptions(merge: true));
      }
      await ref.set({
        'cguVersion': kCguVersion,
        'cguAccepteeLe': FieldValue.serverTimestamp(),
        'majeurDeclare': true,
        'consentMarketing': _consentMarketing,
        'consentMarketingLe': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!existe && _parrainageCtrl.text.trim().isNotEmpty) {
        try {
          await ParrainageService.appliquerCode(_parrainageCtrl.text.trim(), user.uid);
        } catch (_) {}
      }
      if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    } catch (e) {
      if (mounted) setState(() { _enCours = false; _erreur = 'Enregistrement impossible : $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(Tr.s.completerMonProfil),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            child: Text(Tr.s.seDeconnecter, style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(Tr.s.encoreQuelquesInformationsPourVos,
                style: TextStyle(fontSize: 13.5, color: Colors.black87)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _prenomCtrl,
              decoration: InputDecoration(labelText: Tr.s.prenom, border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? Tr.s.requis : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nomCtrl,
              decoration: InputDecoration(labelText: Tr.s.nom, border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? Tr.s.requis : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _quartierCtrl,
              decoration: InputDecoration(labelText: Tr.s.quartier2, border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? Tr.s.requis : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _villeCtrl,
              decoration: InputDecoration(labelText: Tr.s.ville, border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: Tr.s.eMailOptionnel, border: OutlineInputBorder()),
            ),
            if (widget.existant == null) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _parrainageCtrl,
                decoration: InputDecoration(labelText: Tr.s.codeParrainageOptionnel, border: OutlineInputBorder()),
              ),
            ],
            const SizedBox(height: 16),
            _Case(
              valeur: _accepteCgu,
              onChanged: (v) => setState(() => _accepteCgu = v),
              enfant: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(Tr.s.jAiLuJAccepte, style: TextStyle(fontSize: 13)),
                _Lien(Tr.s.conditionsGenerales, () => _ouvrir(1)),
                Text(Tr.s.etLa, style: TextStyle(fontSize: 13)),
                _Lien(Tr.s.politiqueConfidentialite, () => _ouvrir(2)),
                const Text(' *', style: TextStyle(fontSize: 13)),
              ]),
            ),
            _Case(
              valeur: _majeur,
              onChanged: (v) => setState(() => _majeur = v),
              enfant: Text(Tr.s.jeCertifieAvoir18Ans, style: TextStyle(fontSize: 13)),
            ),
            _Case(
              valeur: _consentMarketing,
              onChanged: (v) => setState(() => _consentMarketing = v),
              enfant: Text(Tr.s.jeSouhaiteRecevoirOffresPromotions,
                  style: TextStyle(fontSize: 13)),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 8),
              Text(_erreur!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white),
                onPressed: _enCours ? null : _valider,
                child: _enCours
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(Tr.s.continuer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _ouvrir(int onglet) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => MentionsLegalesPage(ongletInitial: onglet)));
}

class _Case extends StatelessWidget {
  final bool valeur;
  final ValueChanged<bool> onChanged;
  final Widget enfant;
  const _Case({required this.valeur, required this.onChanged, required this.enfant});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => onChanged(!valeur),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Checkbox(value: valeur, onChanged: (v) => onChanged(v ?? false), activeColor: _kPrimary),
          Expanded(child: Padding(padding: const EdgeInsets.only(top: 12), child: enfant)),
        ]),
      );
}

class _Lien extends StatelessWidget {
  final String texte;
  final VoidCallback onTap;
  const _Lien(this.texte, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Text(texte,
            style: const TextStyle(fontSize: 13, color: _kPrimary, decoration: TextDecoration.underline)),
      );
}
