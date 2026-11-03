import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sami/pages/legal/mentions_legales_page.dart';
import 'package:sami/services/parrainage_service.dart';
import 'package:sami/models/utilisateur.dart';
import 'package:sami/pages/accueil_pagneshop.dart';
import 'package:sami/pages/auth/login_page.dart';
import 'package:sami/utils/auth_i18n.dart';
import 'package:sami/services/langue_service.dart';
import 'package:uuid/uuid.dart';
import 'package:sami/l10n/tr.dart';

class SignupPage extends StatefulWidget {
  final AuthLang lang;
  const SignupPage({super.key, this.lang = AuthLang.fr});
  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  // CONSENTEMENTS (loi n° 2024/017 : explicite, libre, non pré-coché ;
  // art. 26 loi n° 2010/021 : le vendeur doit PROUVER le consentement)
  bool _accepteCgu = false;
  bool _majeur = false;
  bool _consentMarketing = false; // facultatif, séparé (art. 7)
  final _formKey       = GlobalKey<FormState>();
  final _nomCtrl       = TextEditingController();
  final _prenomCtrl    = TextEditingController();
  final _telCtrl       = TextEditingController();
  final _emailCtrl     = TextEditingController();
  final _mdpCtrl       = TextEditingController();
  final _confirmCtrl   = TextEditingController();
  final _quartierCtrl  = TextEditingController();
  final _villeCtrl     = TextEditingController(text: 'Garoua');
  final _parainageCtrl = TextEditingController();

  late AuthLang _lang;
  late AuthI18n _i18n;

  bool _mdp1Visible = false;
  bool _mdp2Visible = false;
  bool _enCours     = false;
  String? _erreur;
  int _etape        = 0; // 0=identité, 1=sécurité, 2=localisation

  @override
  void initState() {
    super.initState();
    _lang = widget.lang;
    _i18n = AuthI18n(_lang);
  }

  void _changerLang(AuthLang l) {
    setState(() { _lang = l; _i18n = AuthI18n(l); });
    LangueService.instance.changer(l.name); // langue de toute l'app
  }

  @override
  void dispose() {
    for (final c in [_nomCtrl, _prenomCtrl, _telCtrl, _emailCtrl, _mdpCtrl,
      _confirmCtrl, _quartierCtrl, _villeCtrl, _parainageCtrl]) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Image.asset('lib/assets/images/pagne_back.jpg',
            fit: BoxFit.cover, height: double.infinity, width: double.infinity),
        Container(color: Colors.black.withOpacity(0.45)),
        SafeArea(child: Column(children: [
          // Barre haut : retour + langue
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const Spacer(),
              _SelecteurLang(lang: _lang, onChange: _changerLang),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(children: [
                // Logo
                Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(color: Colors.white,
                      borderRadius: BorderRadius.circular(14)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset('lib/assets/images/logo.png', fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.store, color: Color(0xFF6A1B9A), size: 32)),
                  ),
                ),
                const SizedBox(height: 10),
                Text(_i18n.inscription,
                    style: const TextStyle(color: Colors.white, fontSize: 22,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Colors.black45, blurRadius: 6)])),
                const SizedBox(height: 20),

                // Stepper horizontal
                _StepperHorizontal(etape: _etape, i18n: _i18n),
                const SizedBox(height: 16),

                // Card formulaire
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.97),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: const Offset(0, 8))],
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      // Étape 0 : Identité
                      if (_etape == 0) ...[
                        _Champ(label: _i18n.nom, controller: _nomCtrl, icone: Icons.person_outline,
                            validator: (v) => (v?.isEmpty ?? true) ? _i18n.champRequis : null),
                        const SizedBox(height: 12),
                        _Champ(label: _i18n.prenom, controller: _prenomCtrl, icone: Icons.badge_outlined,
                            validator: (v) => (v?.isEmpty ?? true) ? _i18n.champRequis : null),
                        const SizedBox(height: 12),
                        _Champ(
                          label: _i18n.telephone, controller: _telCtrl,
                          icone: Icons.phone_outlined, type: TextInputType.phone,
                          prefixText: '+237 ',
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                          validator: (v) {
                            final n = (v ?? '')
                                .trim()
                                .replaceAll(RegExp(r'\D'), '');
                            if (n.isEmpty) return _i18n.champRequis;
                            if (!RegExp(r'^6\d{8}$').hasMatch(n)) {
                              return 'Format : 6XXXXXXXX (9 chiffres)';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _Champ(label: _i18n.email, controller: _emailCtrl,
                            icone: Icons.email_outlined, type: TextInputType.emailAddress,
                            validator: (v) {
                              if (v?.isEmpty ?? true) return _i18n.champRequis;
                              if (!(v?.contains('@') ?? false)) return _i18n.emailInvalide;
                              return null;
                            }),
                      ],

                      // Étape 1 : Sécurité
                      if (_etape == 1) ...[
                        _Champ(
                          label: _i18n.motDePasse, controller: _mdpCtrl,
                          icone: Icons.lock_outline, obscure: !_mdp1Visible,
                          suffixIcon: IconButton(
                            icon: Icon(_mdp1Visible ? Icons.visibility : Icons.visibility_off, size: 20, color: Colors.grey),
                            onPressed: () => setState(() => _mdp1Visible = !_mdp1Visible),
                          ),
                          validator: (v) {
                            if (v?.isEmpty ?? true) return _i18n.champRequis;
                            if ((v?.length ?? 0) < 6) return _i18n.mdpTropCourt;
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _Champ(
                          label: _i18n.confirmerMdp, controller: _confirmCtrl,
                          icone: Icons.lock_outline, obscure: !_mdp2Visible,
                          suffixIcon: IconButton(
                            icon: Icon(_mdp2Visible ? Icons.visibility : Icons.visibility_off, size: 20, color: Colors.grey),
                            onPressed: () => setState(() => _mdp2Visible = !_mdp2Visible),
                          ),
                          validator: (v) {
                            if (v?.isEmpty ?? true) return _i18n.champRequis;
                            if (v != _mdpCtrl.text) return _i18n.mdpDiff;
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        // Indicateur de force du mot de passe
                        _IndicateurForceMdp(mdp: _mdpCtrl.text, i18n: _i18n),
                      ],

                      // Étape 2 : Localisation
                      if (_etape == 2) ...[
                        _Champ(label: _i18n.quartier, controller: _quartierCtrl,
                            icone: Icons.location_on_outlined,
                            hint: 'Ex: Lopéré, Yelwa, Plateau…',
                            validator: (v) => (v?.isEmpty ?? true) ? _i18n.champRequis : null),
                        const SizedBox(height: 12),
                        _Champ(label: _i18n.ville, controller: _villeCtrl,
                            icone: Icons.location_city_outlined),
                        const SizedBox(height: 12),
                        _Champ(label: _i18n.codeParrainage, controller: _parainageCtrl,
                            icone: Icons.card_giftcard_outlined),
                        const SizedBox(height: 14),
                        // ── CONSENTEMENTS : jamais pré-cochés, chacun séparé ──
                        _CaseConsentement(
                          valeur: _accepteCgu,
                          onChanged: (v) => setState(() => _accepteCgu = v),
                          enfant: Wrap(children: [
                            Text(Tr.s.jAiLuJAccepte,
                                style: TextStyle(fontSize: 12.5)),
                            _Lien(Tr.s.conditionsGenerales,
                                () => _ouvrirLegal(context, 1)),
                            Text(Tr.s.etLa,
                                style: TextStyle(fontSize: 12.5)),
                            _Lien(Tr.s.politiqueConfidentialite,
                                () => _ouvrirLegal(context, 2)),
                            const Text('. *', style: TextStyle(fontSize: 12.5)),
                          ]),
                        ),
                        _CaseConsentement(
                          valeur: _majeur,
                          onChanged: (v) => setState(() => _majeur = v),
                          enfant: Text(
                              Tr.s.jeCertifieAvoir18Ans,
                              style: TextStyle(fontSize: 12.5)),
                        ),
                        _CaseConsentement(
                          valeur: _consentMarketing,
                          onChanged: (v) =>
                              setState(() => _consentMarketing = v),
                          enfant: Text(
                              Tr.s.jeSouhaiteRecevoirOffresPromotions,
                              style: TextStyle(fontSize: 12.5)),
                        ),
                      ],

                      // Erreur
                      if (_erreur != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_erreur!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                          ]),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Boutons navigation
                      Row(children: [
                        if (_etape > 0) ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => setState(() { _etape--; _erreur = null; }),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF6A1B9A)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Icon(Icons.arrow_back, color: Color(0xFF6A1B9A), size: 20),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _enCours ? null : _prochaine,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6A1B9A),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _enCours
                                  ? const SizedBox(width: 22, height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                  : Text(
                                      _etape == 2 ? _i18n.creerCompte : 'Suivant →',
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                    ),
                            ),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ),

                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(_i18n.dejaCompte, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  TextButton(
                    onPressed: () => Navigator.pushReplacement(context,
                        MaterialPageRoute(builder: (_) => LoginPage())),
                    child: Text(_i18n.connexion,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ]),
              ]),
            ),
          ),
        ])),
      ]),
    );
  }

  Future<void> _prochaine() async {
    setState(() => _erreur = null);
    if (!_formKey.currentState!.validate()) return;

    if (_etape < 2) {
      setState(() => _etape++);
      return;
    }

    // Étape finale → consentements OBLIGATOIRES d'abord
    if (!_accepteCgu || !_majeur) {
      setState(() => _erreur = !_accepteCgu
          ? Tr.s.vousDevezAccepterConditionsGenerales
          : Tr.s.serviceEstReservePersonnesMajeures);
      return;
    }
    setState(() => _enCours = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _mdpCtrl.text,
      );
      // ── UNICITÉ DU TÉLÉPHONE ── (vérifiée APRÈS création : les règles
      // exigent d'être connecté pour lire ; si doublon → on ANNULE le
      // compte tout juste créé — un numéro = un compte, vital pour le
      // Mobile Money et les livraisons).
      final telNet = _telCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
      final dejaLa = await FirebaseFirestore.instance
          .collection('utilisateurs')
          .where('telephone', isEqualTo: telNet)
          .limit(1)
          .get();
      if (dejaLa.docs.isNotEmpty) {
        await cred.user?.delete();
        if (mounted) {
          setState(() {
            _enCours = false;
            _erreur =
                'Ce numéro de téléphone est déjà lié à un compte. '
                'Connectez-vous, ou utilisez « Mot de passe oublié ».';
          });
        }
        return;
      }
      // ── EMAIL DE VÉRIFICATION ── (non bloquant : le compte marche,
      // mais l'adresse est prouvée — utile avant tout litige/SAV)
      try {
        await cred.user?.sendEmailVerification();
      } catch (_) {}

      final uid = cred.user!.uid;
      final codeParrainage = 'SAMI-${_nomCtrl.text.toUpperCase().substring(0, min(6, _nomCtrl.text.length))}-${const Uuid().v4().substring(0, 4).toUpperCase()}';

      final user = Utilisateur(
        id: uid,
        image: '',
        nom: _nomCtrl.text.trim(),
        prenom: _prenomCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        adresse: '${_quartierCtrl.text}, ${_villeCtrl.text}',
        telephone: '+237${_telCtrl.text.trim()}',
        dateInscription: DateTime.now(),
        derniereConnexion: DateTime.now(),
        estVerifie: false,
        estActif: true,
        role: 'client',
        historiqueCommandes: [],
        panier: [],
        favoris: [],
        methodesPaiement: [],
        adresseLivraison: ['${_quartierCtrl.text}, ${_villeCtrl.text}, Cameroun'],
        langue: _lang.name,
        notifications: true,
        quartier: _quartierCtrl.text.trim(),
        ville: _villeCtrl.text.trim(),
        pays: 'Cameroun',
        niveau: 1,
        pointsFidelite: 0,
        creditBalance: 0,
        codeParrainage: codeParrainage,
      );

      await FirebaseFirestore.instance.collection('utilisateurs').doc(uid).set(user.toMap());
      // PREUVE DU CONSENTEMENT (art. 26 loi 2010/021 ; loi 2024/017) :
      // version des CGU acceptée, horodatage serveur, majorité déclarée,
      // choix marketing — relisibles en cas de litige ou de contrôle.
      await FirebaseFirestore.instance.collection('utilisateurs').doc(uid).set({
        'cguVersion': kCguVersion,
        'cguAccepteeLe': FieldValue.serverTimestamp(),
        'majeurDeclare': true,
        'consentMarketing': _consentMarketing,
        'consentMarketingLe': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Appliquer le parrainage si code saisi
      if (_parainageCtrl.text.trim().isNotEmpty) {
        await _appliquerParrainage(_parainageCtrl.text.trim(), uid);
      }

      if (mounted) {
        Navigator.pushAndRemoveUntil(context,
            MaterialPageRoute(builder: (_) => const AccueilPagneShop()), (_) => false);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _erreur = _i18n.erreurFirebase(e.code));
    } catch (e) {
      if (mounted) setState(() => _erreur = _i18n.erreurFirebase('unknown'));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _appliquerParrainage(String code, String nouvelUid) async {
    // Version SAINE : aucun crédit ici (l'ancien code écrivait les soldes
    // directement — fraude facile ET bloqué par les règles anti-crédit).
    // Le lien est créé « en attente » ; la récompense tombera à la
    // PREMIÈRE LIVRAISON du filleul, via la file staff.
    try {
      await ParrainageService.appliquerCode(code, nouvelUid);
    } catch (_) {}
  }

  int min(int a, int b) => a < b ? a : b;
}

// ─── Stepper horizontal ───────────────────────────────────────────────────────

class _StepperHorizontal extends StatelessWidget {
  final int etape;
  final AuthI18n i18n;
  const _StepperHorizontal({required this.etape, required this.i18n});

  @override
  Widget build(BuildContext context) {
    final labels = ['Identité', 'Sécurité', 'Adresse'];
    return Row(
      children: List.generate(3, (i) => Expanded(
        child: Row(
          children: [
            Expanded(child: Column(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 28, height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i <= etape ? const Color(0xFF6A1B9A) : Colors.white.withOpacity(0.3),
                  border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5),
                ),
                child: Center(child: i < etape
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                    : Text('${i + 1}', style: TextStyle(
                        color: i == etape ? Colors.white : Colors.white60,
                        fontSize: 12, fontWeight: FontWeight.bold))),
              ),
              const SizedBox(height: 4),
              Text(labels[i], style: TextStyle(
                  color: i <= etape ? Colors.white : Colors.white60,
                  fontSize: 10)),
            ])),
            if (i < 2) Container(height: 1, width: 20,
                color: i < etape ? Colors.white : Colors.white30),
          ],
        ),
      )),
    );
  }
}

// ─── Indicateur de force du mot de passe ─────────────────────────────────────

class _IndicateurForceMdp extends StatelessWidget {
  final String mdp;
  final AuthI18n i18n;
  const _IndicateurForceMdp({required this.mdp, required this.i18n});

  @override
  Widget build(BuildContext context) {
    if (mdp.isEmpty) return const SizedBox.shrink();
    int force = 0;
    if (mdp.length >= 8) force++;
    if (mdp.contains(RegExp(r'[A-Z]'))) force++;
    if (mdp.contains(RegExp(r'[0-9]'))) force++;
    if (mdp.contains(RegExp(r'[!@#$%^&*]'))) force++;

    final (couleur, label) = switch (force) {
      0 || 1 => (Colors.red, '🔴 Faible'),
      2      => (Colors.orange, '🟠 Moyen'),
      3      => (Colors.amber, '🟡 Bon'),
      _      => (Colors.green, '🟢 Fort'),
    };
    return Row(children: [
      Expanded(child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: force / 4,
          backgroundColor: Colors.grey.shade200,
          valueColor: AlwaysStoppedAnimation(couleur),
          minHeight: 6,
        ),
      )),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(fontSize: 11, color: couleur, fontWeight: FontWeight.w500)),
    ]);
  }
}

// ─── Réutilisation de _Champ depuis login_page.dart ─────────────────────────

class _Champ extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icone;
  final TextInputType type;
  final bool obscure;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final String? prefixText;
  final String? hint;
  final List<TextInputFormatter>? inputFormatters;

  const _Champ({required this.label, required this.controller, required this.icone,
    this.type = TextInputType.text, this.obscure = false, this.suffixIcon,
    this.validator, this.prefixText, this.hint, this.inputFormatters});

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller, keyboardType: type, obscureText: obscure,
    textInputAction: TextInputAction.next,
    inputFormatters: inputFormatters,
    validator: validator,
    decoration: InputDecoration(
      labelText: label, hintText: hint, prefixText: prefixText,
      prefixIcon: Icon(icone, size: 20, color: Colors.grey.shade500),
      suffixIcon: suffixIcon,
      filled: true, fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF6A1B9A), width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
    ),
  );
}

class _SelecteurLang extends StatelessWidget {
  final AuthLang lang;
  final ValueChanged<AuthLang> onChange;
  const _SelecteurLang({required this.lang, required this.onChange});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: AuthLang.values.where((l) => l != AuthLang.ff).map((l) {
      final actif = l == lang;
      return GestureDetector(
        onTap: () => onChange(l),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: actif ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(20)),
          child: Text(switch (l) { AuthLang.fr => '🇫🇷', AuthLang.en => '🇬🇧', AuthLang.ff => '🟡' },
              style: TextStyle(fontSize: actif ? 16 : 14)),
        ),
      );
    }).toList()),
  );
}

// ─── Consentement : case jamais pré-cochée, libellé cliquable ─────────────
void _ouvrirLegal(BuildContext context, int onglet) {
  Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => MentionsLegalesPage(ongletInitial: onglet)));
}

class _CaseConsentement extends StatelessWidget {
  final bool valeur;
  final ValueChanged<bool> onChanged;
  final Widget enfant;
  const _CaseConsentement(
      {required this.valeur, required this.onChanged, required this.enfant});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => onChanged(!valeur),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Checkbox(
                  value: valeur,
                  activeColor: const Color(0xFF6A1B9A),
                  onChanged: (v) => onChanged(v ?? false)),
            ),
            const SizedBox(width: 4),
            Expanded(
                child: Padding(
                    padding: const EdgeInsets.only(top: 7), child: enfant)),
          ]),
        ),
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
            style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF6A1B9A),
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w600)),
      );
}
