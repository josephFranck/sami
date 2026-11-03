import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:sami/services/parametres_service.dart';
import 'package:sami/services/parrainage_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sami/pages/legal/mentions_legales_page.dart';
import 'package:sami/widgets/image_universelle.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sami/services/config_marketing_service.dart';
import 'package:sami/services/fidelite_service.dart';
import 'package:sami/models/utilisateur.dart';
import 'package:sami/pages/auth/login_page.dart';
import 'package:sami/pages/commandes/mes_commandes_page.dart';
import 'package:sami/pages/panierpage.dart';
import 'package:sami/services/stockage_service.dart';
import 'package:sami/utils/prix_fcfa.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kAccent = Color(0xFFFF8F00);

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  ConfigMarketing? _cfg;
  Utilisateur? _u;
  bool _consentMarketing = false;

  Future<void> _chargerConsentMarketing() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final d = await FirebaseFirestore.instance
          .collection('utilisateurs').doc(uid).get();
      if (mounted) {
        setState(() =>
            _consentMarketing = d.data()?['consentMarketing'] == true);
      }
    } catch (_) {}
  }

  Future<void> _changerConsentMarketing(bool v) async {
    setState(() => _consentMarketing = v);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await FirebaseFirestore.instance.collection('utilisateurs').doc(uid).set({
        'consentMarketing': v,
        'consentMarketingLe': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// SUPPRESSION DU COMPTE — droit à l'effacement (loi n° 2024/017).
  /// Les données d'IDENTIFICATION sont effacées/anonymisées ; les
  /// enregistrements de transactions (commandes, paiements, preuves de
  /// livraison) sont CONSERVÉS anonymisés pour la durée légale
  /// (art. 32 loi 2010/021 ; obligations comptables) — ils ne sont plus
  /// rattachables à la personne.
  Future<void> _supprimerMonCompte() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer définitivement votre compte ?'),
        content: const Text(
            'Vos informations personnelles (nom, téléphone, courriel, '
            'adresses, profils de mesures, panier) seront effacées. '
            'Vos commandes passées sont conservées sous forme anonymisée '
            'pour la durée légale. Vos crédits non utilisés seront perdus.\n\n'
            'Cette action est irréversible.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;
    final db = FirebaseFirestore.instance;
    try {
      // 1. Profils de mesures (données personnelles) → supprimés
      final mesures = await db
          .collection('utilisateurs').doc(uid).collection('mesures').get();
      for (final d in mesures.docs) {
        await d.reference.delete();
      }
      // 2. Panier → supprimé
      try {
        await db.collection('paniers').doc(uid).delete();
      } catch (_) {}
      // 3. Compte → ANONYMISÉ (le doc reste : clé des commandes passées)
      await db.collection('utilisateurs').doc(uid).set({
        'nom': 'Compte supprimé',
        'prenom': '',
        'email': 'supprime-$uid@anonyme.invalid',
        'telephone': '',
        'image': '',
        'adresse': '',
        'adresseLivraison': [],
        'quartier': '',
        'favoris': [],
        'methodesPaiement': [],
        'estActif': false,
        'compteSupprime': true,
        'compteSupprimeLe': FieldValue.serverTimestamp(),
        'consentMarketing': false,
      }, SetOptions(merge: true));
      // 4. Identité d'authentification → supprimée
      try {
        await user.delete();
      } on FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login') {
          // Firebase exige une connexion récente : on déconnecte et on
          // demande de se reconnecter puis de recommencer.
          await FirebaseAuth.instance.signOut();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 8),
              content: Text(
                  'Par sécurité, reconnectez-vous puis relancez la '
                  'suppression : vos données ont déjà été anonymisées.')));
          Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
          return;
        }
        rethrow;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.green,
          content: Text('Compte supprimé. Vos données ont été effacées.')));
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('Suppression impossible : $e')));
    }
  }

  bool _chargement = true;
  double _uploadProgress = 0;
  bool _uploadEnCours = false;

  @override
  void initState() { super.initState(); _charger(); _chargerConsentMarketing(); }

  Future<void> _editerProfil() async {
    if (_u == null) return;
    final nomCtrl = TextEditingController(text: _u!.nom);
    final prenomCtrl = TextEditingController(text: _u!.prenom);
    final telCtrl = TextEditingController(text: _u!.telephone);
    final quartierCtrl = TextEditingController(text: _u!.quartier);
    final villeCtrl = TextEditingController(text: _u!.ville);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifier mon profil'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _champEdit(prenomCtrl, 'Prénom'),
              _champEdit(nomCtrl, 'Nom'),
              _champEdit(telCtrl, 'Téléphone', clavier: TextInputType.phone),
              _champEdit(quartierCtrl, 'Quartier'),
              _champEdit(villeCtrl, 'Ville'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        await Utilisateur.utilisateurCollection
            .doc(FirebaseAuth.instance.currentUser!.uid)
            .update({
          'nom': nomCtrl.text.trim(),
          'prenom': prenomCtrl.text.trim(),
          'telephone': telCtrl.text.trim(),
          'quartier': quartierCtrl.text.trim(),
          'ville': villeCtrl.text.trim(),
        });
        await _charger(); // recharge l'affichage
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Profil mis à jour'), backgroundColor: Colors.green));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Erreur de mise à jour'), backgroundColor: Colors.red));
        }
      }
    }
  }

  Widget _champEdit(TextEditingController ctrl, String label,
      {TextInputType? clavier}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: ctrl,
        keyboardType: clavier,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Future<void> _charger() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { setState(() => _chargement = false); return; }
    // Points/parrainage des livraisons non encore comptées : le client
    // les réclame ici (seul autorisé à écrire sur son doc), AVANT lecture.
    await FideliteService.reclamerTout(user.uid);
    final cfg = await FideliteService.config();
    final u = await Utilisateur.fromUid(user.uid);
    if (mounted) setState(() { _u = u; _cfg = cfg; _chargement = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_chargement) return const Scaffold(body: Center(child: CircularProgressIndicator(color: _kPrimary)));
    if (_u == null) return Scaffold(body: Center(child: ElevatedButton(onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage())), child: const Text('Se connecter'))));

    // Paliers de la CONFIG ADMIN — les mêmes que le devis (réduction
    // livraison) ; avant : constantes NiveauFidelite, différentes du devis.
    final cfg = _cfg ?? ConfigMarketing.defaut();
    final niveau = FideliteService.palierPour(cfg, _u!.pointsFidelite);
    final suivant = FideliteService.palierSuivant(cfg, _u!.pointsFidelite);
    final pct = suivant != null ? ((_u!.pointsFidelite - niveau.pointsRequis) / (suivant.pointsRequis - niveau.pointsRequis)).clamp(0.0, 1.0) : 1.0;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: _kPrimary,
            foregroundColor: Colors.white,
            title: const Text('Mon profil'),
            actions: [
              IconButton(icon: const Icon(Icons.edit), onPressed: _editerProfil),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: _handleMenu,
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'stockage', child: Text('Paramètres stockage')),
                  const PopupMenuItem(value: 'parrainage', child: Text('Mon code parrainage')),
                  const PopupMenuItem(value: 'logout', child: Text('Déconnexion')),
                ],
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: _kPrimary,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 48),
                    GestureDetector(
                      onTap: _changerPhoto,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 44,
                            backgroundColor: Colors.white24,
                            backgroundImage: providerUniversel(_u!.image),
                            child: _u!.image.isEmpty ? Text(_u!.nom.isNotEmpty ? _u!.nom[0].toUpperCase() : '?', style: const TextStyle(fontSize: 32, color: Colors.white, fontWeight: FontWeight.bold)) : null,
                          ),
                          if (_uploadEnCours) Positioned.fill(child: CircularProgressIndicator(value: _uploadProgress, strokeWidth: 3, color: _kAccent)),
                          Positioned(bottom: 0, right: 0, child: Container(width: 26, height: 26, decoration: const BoxDecoration(color: _kAccent, shape: BoxShape.circle), child: const Icon(Icons.camera_alt, size: 14, color: Colors.white))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('${_u!.prenom} ${_u!.nom}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(_u!.email, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(14),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Fidélité
                _buildCardFidelite(niveau, suivant, pct),
                const SizedBox(height: 14),
                // Stats
                _buildStats(),
                const SizedBox(height: 14),
                // Actions
                _buildActions(),
                const SizedBox(height: 14),
                // Infos
                _buildInfos(),
                const SizedBox(height: 14),
                // Stockage : réglage TECHNIQUE réservé à l'admin
                if (_u?.role == 'admin') _buildCardStockage(),
                const SizedBox(height: 24),
                // ── Droits sur les données (loi n° 2024/017) ──
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.gavel_outlined, color: Colors.grey),
                  title: const Text('Mentions légales, CGU et confidentialité',
                      style: TextStyle(fontSize: 13.5)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MentionsLegalesPage())),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Recevoir les offres et promotions',
                      style: TextStyle(fontSize: 13.5)),
                  subtitle: const Text('Retirable à tout moment',
                      style: TextStyle(fontSize: 11)),
                  value: _consentMarketing,
                  activeColor: const Color(0xFF6A1B9A),
                  onChanged: _changerConsentMarketing,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _deconnecter,
                  icon: const Icon(Icons.logout, color: Colors.red, size: 18),
                  label: const Text('Déconnexion', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), minimumSize: const Size(double.infinity, 48)),
                ),
                const SizedBox(height: 10),
                // DROIT À L'EFFACEMENT : suppression définitive du compte
                TextButton(
                  onPressed: _supprimerMonCompte,
                  child: Text('Supprimer mon compte',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5,
                          decoration: TextDecoration.underline)),
                ),
                const SizedBox(height: 24),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardFidelite(PalierConfig niveau, PalierConfig? suivant, double pct) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: _kPrimary, borderRadius: BorderRadius.circular(16)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(niveau.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(niveau.nom, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              Text('${_u!.pointsFidelite} points · -${niveau.reductionLivraison.round()}% livraison · ${niveau.cashback.toStringAsFixed(niveau.cashback % 1 == 0 ? 0 : 1)}% cashback', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ])),
            if (_u!.creditBalance > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: _kAccent, borderRadius: BorderRadius.circular(8)),
                child: Text(PrixFCFA.formaterCompact(_u!.creditBalance), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        if (suivant != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: pct, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(_kAccent), minHeight: 6),
          ),
          const SizedBox(height: 4),
          Text('${suivant.pointsRequis - _u!.pointsFidelite} pts pour ${suivant.emoji} ${suivant.nom}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ],
    ),
  );

  Widget _buildStats() => StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance.collection('sessions_commande').where('clientId', isEqualTo: _u!.id).snapshots(),
    builder: (context, snap) {
      final nb = snap.data?.docs.length ?? 0;
      return Row(
        children: [
          _statCard(Icons.receipt_long, 'Commandes', '$nb', Colors.teal),
          const SizedBox(width: 10),
          _statCard(Icons.favorite, 'Favoris', '${_u!.favoris.length}', Colors.pink),
          const SizedBox(width: 10),
          _statCard(Icons.account_balance_wallet, 'Crédits', _u!.creditBalance > 0 ? PrixFCFA.formaterCompact(_u!.creditBalance) : '0', _kPrimary),
        ],
      );
    },
  );

  Widget _statCard(IconData i, String l, String v, Color c) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade100)),
      child: Column(
        children: [
          Icon(i, color: c, size: 22),
          const SizedBox(height: 4),
          Text(v, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: c)),
          Text(l, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    ),
  );

  Widget _buildActions() => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade100)),
    child: Column(
      children: [
        _actionTile(Icons.shopping_bag_outlined, 'Mon panier', Colors.indigo, () => Navigator.push(context, MaterialPageRoute(builder: (_) => PanierPage(utilisateur: _u!)))),
        const Divider(height: 1, indent: 56),
        _actionTile(Icons.receipt_long_outlined, 'Mes commandes', Colors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MesCommandesPage()))),
        const Divider(height: 1, indent: 56),
        _actionTile(Icons.favorite_border, 'Mes favoris', Colors.pink, () => Navigator.pushNamed(context, '/favoris')),
        const Divider(height: 1, indent: 56),
        // Les crédits sont des AVOIRS (remboursements, parrainage) : pas de
        // rechargement en argent (décision 03/11/2026).
        _actionTile(Icons.account_balance_wallet_outlined, 'Mes avoirs', Colors.amber.shade800, () => Navigator.pushNamed(context, '/avoirs')),
        const Divider(height: 1, indent: 56),
        _actionTile(Icons.card_giftcard, 'Mon code de parrainage', Colors.purple, _showCodeParrainage),
        const Divider(height: 1, indent: 56),
        _actionTile(Icons.lock_outline, 'Sécurité (email / mot de passe)', Colors.blueGrey, _securiteCompte),
        const Divider(height: 1, indent: 56),
        _actionTile(Icons.chat_bubble_outline, 'Mes messages', Colors.orange, () => Navigator.pushNamed(context, '/chatpage')),
        if (_u!.aRole('couturier')) ...[const Divider(height: 1, indent: 56), _actionTile(Icons.content_cut, 'Espace couturier', Colors.teal, () => Navigator.pushNamed(context, '/dashboard_couturier'))],
        const Divider(height: 1, indent: 56),
        _actionTile(Icons.workspace_premium, 'Abonnements', Color(0xFFBA7517), () => Navigator.pushNamed(context, '/abonnements')),
      ],
    ),
  );

  /// Changer email/mot de passe exige de REprouver son identité
  /// (règle Firebase) : mot de passe actuel, puis les nouveautés.
  Future<void> _securiteCompte() async {
    final actuel = TextEditingController();
    final nouvelEmail = TextEditingController();
    final nouveauMdp = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sécurité du compte'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: actuel,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Mot de passe ACTUEL (obligatoire)',
                  border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(
              controller: nouvelEmail,
              decoration: const InputDecoration(
                  labelText: 'Nouvel email (optionnel)',
                  border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(
              controller: nouveauMdp,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Nouveau mot de passe (optionnel, 6+)',
                  border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Appliquer')),
        ],
      ),
    );
    if (ok != true) return;
    final u = FirebaseAuth.instance.currentUser;
    if (u?.email == null) return;
    try {
      await u!.reauthenticateWithCredential(EmailAuthProvider.credential(
          email: u.email!, password: actuel.text));
      var msg = '';
      if (nouveauMdp.text.trim().length >= 6) {
        await u.updatePassword(nouveauMdp.text.trim());
        msg = 'Mot de passe changé ✅';
      }
      if (nouvelEmail.text.trim().contains('@')) {
        await u.verifyBeforeUpdateEmail(nouvelEmail.text.trim());
        msg +=
            '${msg.isEmpty ? '' : '  ·  '}Un lien de confirmation a été envoyé au nouvel email 📧';
      }
      if (mounted && msg.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(msg), backgroundColor: Colors.green));
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.code == 'wrong-password' ||
                    e.code == 'invalid-credential'
                ? 'Mot de passe actuel incorrect.'
                : 'Erreur : ${e.code}'),
            backgroundColor: Colors.red));
      }
    } finally {
      actuel.dispose();
      nouvelEmail.dispose();
      nouveauMdp.dispose();
    }
  }

  Future<void> _partagerCode() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final actif = await ParametresService.parrainageActif();
    final code = await ParrainageService.monCode(uid);
    if (!mounted) return;
    if (!actif) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Le programme de parrainage arrive bientôt 🎁')));
      return;
    }
    await Share.share(
        'Rejoins-moi sur PagneShop 🧵 Les plus beaux pagnes de Garoua, '
        'livrés chez toi. Inscris-toi avec mon code $code et gagne des '
        'crédits à ta première commande livrée !');
  }

  Widget _actionTile(IconData ic, String label, Color c, VoidCallback onTap) => ListTile(
    leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(ic, color: c, size: 18)),
    title: Text(label, style: const TextStyle(fontSize: 14)),
    trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
    onTap: onTap, dense: true,
  );

  Widget _buildInfos() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade100)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Informations', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 10),
        _infoLigne(Icons.phone, _u!.telephone),
        _infoLigne(Icons.location_on_outlined, '${_u!.quartier}, ${_u!.ville}'),
        if (_u!.adresseLivraison.isNotEmpty) _infoLigne(Icons.home_outlined, _u!.adresseLivraison.first),
      ],
    ),
  );

  Widget _infoLigne(IconData ic, String txt) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [Icon(ic, size: 16, color: Colors.grey), const SizedBox(width: 8), Expanded(child: Text(txt, style: const TextStyle(fontSize: 13)))]),
  );

  Widget _buildCardStockage() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade100)),
    child: Row(
      children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: StockageService.estCloudflare ? Colors.orange.shade50 : Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.cloud_outlined, color: StockageService.estCloudflare ? Colors.orange : Colors.blue, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Stockage photos', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          Text(StockageService.estCloudflare ? 'Cloudflare R2 — actif' : 'Firebase Storage — actif',
            style: TextStyle(fontSize: 11, color: StockageService.estCloudflare ? Colors.orange : Colors.blue)),
        ])),
        TextButton(onPressed: _showStockageDialog, child: const Text('Changer', style: TextStyle(fontSize: 12))),
      ],
    ),
  );

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _changerPhoto() async {
    final photo = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (photo == null || !mounted) return;
    setState(() { _uploadEnCours = true; _uploadProgress = 0; });
    try {
      final url = await StockageService.uploadXFile(
          fichier: photo,
        dossier: 'profils',
        nomFichier: '${FirebaseAuth.instance.currentUser!.uid}.jpg',
        onProgress: (p) => setState(() => _uploadProgress = p),
      );
      await Utilisateur.utilisateurCollection.doc(FirebaseAuth.instance.currentUser!.uid).update({'image': url});
      await _charger();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _uploadEnCours = false);
    }
  }

  void _handleMenu(String val) {
    if (val == 'stockage') _showStockageDialog();
    else if (val == 'parrainage') _showCodeParrainage();
    else if (val == 'logout') _deconnecter();
  }

  void _showStockageDialog() {
    showDialog(context: context, builder: (_) => _DialogStockage(onChanged: () => setState(() {})));
  }

  /// Code de parrainage RÉEL (généré/lu par ParrainageService) et montants
  /// RÉELS des paramètres admin — plus de code inventé ni de 500/1 000 en dur.
  Future<void> _showCodeParrainage() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final actif = await ParametresService.parrainageActif();
    if (!mounted) return;
    if (!actif) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Le programme de parrainage arrive bientôt 🎁')));
      return;
    }
    final code = await ParrainageService.monCode(uid);
    final gainParrain = await ParametresService.recompenseParrainF();
    final gainFilleul = await ParametresService.recompenseFilleulF();
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Mon code de parrainage'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: _kPrimary.withOpacity(0.08), borderRadius: BorderRadius.circular(12)), child: Text(code, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _kPrimary, letterSpacing: 2))),
        const SizedBox(height: 10),
        Text('Votre filleul gagne ${PrixFCFA.formater(gainFilleul)} d\'avoir\nVous gagnez ${PrixFCFA.formater(gainParrain)} d\'avoir\nà sa première commande livrée.',
            textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 13)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
        ElevatedButton.icon(
          icon: const Icon(Icons.share, size: 16),
          label: const Text('Partager'),
          onPressed: () { Navigator.pop(ctx); _partagerCode(); },
        ),
      ],
    ));
  }

  Future<void> _deconnecter() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Déconnexion'),
      content: const Text('Voulez-vous vraiment vous déconnecter ?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Déconnecter', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok == true && mounted) {
      await FirebaseAuth.instance.signOut();
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
    }
  }
}

// ─── Dialog switch stockage ───────────────────────────────────────────────────

class _DialogStockage extends StatefulWidget {
  final VoidCallback onChanged;
  const _DialogStockage({required this.onChanged});
  @override
  State<_DialogStockage> createState() => _DialogStockageState();
}

class _DialogStockageState extends State<_DialogStockage> {
  bool _cloudflare = StockageService.estCloudflare;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Row(children: [Icon(Icons.cloud_outlined, color: _kPrimary, size: 20), SizedBox(width: 8), Flexible(child: Text('Stockage des photos', overflow: TextOverflow.ellipsis))]),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _option('Firebase Storage', '\$0.026/Go stocké · \$0.12/Go téléch.', false, Icons.whatshot, Colors.orange),
        const SizedBox(height: 10),
        _option('Cloudflare R2', '\$0.015/Go stocké · téléch. GRATUIT', true, Icons.cloud_outlined, Colors.blue, badge: 'Recommandé'),
        if (_cloudflare) ...[
          const SizedBox(height: 10),
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
            child: const Text('Configure _R2Config dans\nlib/services/stockage_service.dart\navant d\'activer R2.', style: TextStyle(fontSize: 11, color: Colors.blue))),
        ],
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
      ElevatedButton(
        onPressed: () async {
          await StockageService.activerCloudflare(_cloudflare);
          widget.onChanged();
          if (context.mounted) Navigator.pop(context);
        },
        style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white),
        child: const Text('Appliquer'),
      ),
    ],
  );

  Widget _option(String titre, String sub, bool valeur, IconData ic, Color c, {String? badge}) => GestureDetector(
    onTap: () => setState(() => _cloudflare = valeur),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cloudflare == valeur ? c.withOpacity(0.08) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _cloudflare == valeur ? c : Colors.grey.shade300, width: _cloudflare == valeur ? 2 : 1),
      ),
      child: Row(
        children: [
          Icon(ic, color: c, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(titre, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: c, fontSize: 13))),
              if (badge != null) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(4)), child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)))],
            ]),
            Text(sub, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ])),
          if (_cloudflare == valeur) Icon(Icons.check_circle, color: c, size: 18),
        ],
      ),
    ),
  );
}
