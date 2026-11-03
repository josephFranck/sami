import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sami/pages/accueil_pagneshop.dart';
import 'package:sami/pages/auth/reset_password_page.dart';
import 'package:sami/pages/auth/signup_page.dart';
import 'package:sami/utils/auth_i18n.dart';
import 'package:sami/services/langue_service.dart';
import 'package:sami/pages/auth/connexion_telephone_page.dart';
import 'package:sami/l10n/tr.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _mdpCtrl   = TextEditingController();

  AuthLang _lang = AuthLang.fr;
  bool _mdpVisible = false;
  bool _enCours    = false;
  String? _erreur;

  late AuthI18n _i18n;

  @override
  void initState() {
    super.initState();
    _i18n = AuthI18n(_lang);
    _chargerLang();
  }

  // La langue est celle de TOUTE l'app (LangueService, même clé de
  // préférence `auth_lang` qu'avant) : choisir ici vaut pour tous les écrans.
  Future<void> _chargerLang() async {
    final saved = LangueService.instance.langue;
    setState(() {
      _lang = AuthLang.values.firstWhere((l) => l.name == saved, orElse: () => AuthLang.fr);
      _i18n = AuthI18n(_lang);
    });
  }

  void _changerLang(AuthLang l) {
    setState(() { _lang = l; _i18n = AuthI18n(l); });
    LangueService.instance.changer(l.name);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _mdpCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        // ── Fond image pagne ──────────────────────────────────────────────
        Image.asset('lib/assets/images/pagne_back.jpg',
            fit: BoxFit.cover, height: double.infinity, width: double.infinity),
        // ── Overlay sombre ────────────────────────────────────────────────
        Container(color: Colors.black.withOpacity(0.45)),
        // ── Contenu ───────────────────────────────────────────────────────
        SafeArea(
          child: Column(children: [
            // Sélecteur de langue en haut à droite
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _SelecteurLang(lang: _lang, onChange: _changerLang),
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(children: [
                    // Logo + Nom
                    _LogoHeader(i18n: _i18n),
                    const SizedBox(height: 32),
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
                          Text(_i18n.connexion,
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF6A1B9A))),
                          const SizedBox(height: 4),
                          Text(_i18n.bienvenue,
                              style: const TextStyle(fontSize: 14, color: Colors.grey)),
                          const SizedBox(height: 24),

                          // Email
                          _Champ(
                            label: _i18n.email,
                            controller: _emailCtrl,
                            icone: Icons.email_outlined,
                            type: TextInputType.emailAddress,
                            validator: (v) {
                              if (v == null || v.isEmpty) return _i18n.champRequis;
                              if (!v.contains('@') || !v.contains('.')) return _i18n.emailInvalide;
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // Mot de passe
                          _Champ(
                            label: _i18n.motDePasse,
                            controller: _mdpCtrl,
                            icone: Icons.lock_outline,
                            obscure: !_mdpVisible,
                            suffixIcon: IconButton(
                              icon: Icon(_mdpVisible ? Icons.visibility : Icons.visibility_off, size: 20, color: Colors.grey),
                              onPressed: () => setState(() => _mdpVisible = !_mdpVisible),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) return _i18n.champRequis;
                              if (v.length < 6) return _i18n.mdpTropCourt;
                              return null;
                            },
                          ),

                          // Mot de passe oublié
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => ResetPasswordPage(lang: _lang))),
                              child: Text(_i18n.mdpOublie,
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF6A1B9A))),
                            ),
                          ),

                          // Erreur
                          if (_erreur != null) ...[
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
                            const SizedBox(height: 12),
                          ],

                          // Bouton connexion
                          SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _enCours ? null : _seConnecter,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6A1B9A),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 2,
                              ),
                              child: _enCours
                                  ? const SizedBox(width: 22, height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                  : Text(_i18n.seConnecter,
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            ),
                          ),

                          // Connexion par téléphone (SMS) / WhatsApp — lot C,
                          // affichée quand l'exploitant a activé le canal
                          FutureBuilder<List<CanalCode>>(
                            future: ConnexionTelephonePage.canauxActifs(),
                            builder: (_, snap) {
                              final canaux = snap.data ?? const <CanalCode>[];
                              if (canaux.isEmpty) return const SizedBox.shrink();
                              return Column(children: [
                                const SizedBox(height: 12),
                                Row(children: [
                                  Expanded(child: Divider(color: Colors.grey.shade300)),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    child: Text(_lang == AuthLang.en ? 'or' : 'ou',
                                        style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                  ),
                                  Expanded(child: Divider(color: Colors.grey.shade300)),
                                ]),
                                const SizedBox(height: 8),
                                for (final c in canaux)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: SizedBox(
                                      height: 46,
                                      child: OutlinedButton.icon(
                                        onPressed: () => Navigator.push(context, MaterialPageRoute(
                                            builder: (_) => ConnexionTelephonePage(canalInitial: c))),
                                        icon: Icon(c == CanalCode.sms ? Icons.sms_outlined : Icons.chat,
                                            color: c == CanalCode.sms ? const Color(0xFF6A1B9A) : const Color(0xFF25D366)),
                                        label: Text(
                                          c == CanalCode.sms
                                              ? (_lang == AuthLang.en ? 'Continue with phone (SMS)' : Tr.s.continuerAvecTelephoneSms)
                                              : (_lang == AuthLang.en ? 'Continue with WhatsApp' : Tr.s.continuerAvecWhatsapp),
                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.black87,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      ),
                                    ),
                                  ),
                              ]);
                            },
                          ),

                          const SizedBox(height: 20),
                          // Lien inscription
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(_i18n.pasDeCompte, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                            TextButton(
                              onPressed: () => Navigator.pushReplacement(context,
                                  MaterialPageRoute(builder: (_) => SignupPage(lang: _lang))),
                              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
                              child: Text(_i18n.sInscrire,
                                  style: const TextStyle(color: Color(0xFF6A1B9A), fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ]),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(Tr.s.k2025SamiGaroua,
                        style: TextStyle(color: Colors.white60, fontSize: 11)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _seConnecter() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _enCours = true; _erreur = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _mdpCtrl.text,
      );
      // Mise à jour dernière connexion
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('utilisateurs').doc(uid)
            .update({'derniereConnexion': FieldValue.serverTimestamp(), 'langue': _lang.name});
      }
      if (mounted) {
        Navigator.pushAndRemoveUntil(context,
            MaterialPageRoute(builder: (_) => const AccueilPagneShop()), (_) => false);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _erreur = _i18n.erreurFirebase(e.code));
    } catch (_) {
      if (mounted) setState(() => _erreur = _i18n.erreurFirebase('unknown'));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }
}
// ─── Widgets partagés ─────────────────────────────────────────────────────────

class _LogoHeader extends StatelessWidget {
  final AuthI18n i18n;
  const _LogoHeader({required this.i18n});

  @override
  Widget build(BuildContext context) => Column(children: [
    Container(
      width: 84, height: 84,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12)]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.asset('lib/assets/images/logo.png', fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(Icons.store, color: Color(0xFF6A1B9A), size: 44)),
      ),
    ),
    const SizedBox(height: 14),
    Text(i18n.appNom,
        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white,
            fontFamily: 'DancingScript', shadows: [Shadow(color: Colors.black45, blurRadius: 8)])),
    const SizedBox(height: 4),
    SizedBox(
      width: 220,
      child: AnimatedTextKit(
        repeatForever: true,
        animatedTexts: [
          TyperAnimatedText(i18n.appSlogan, speed: const Duration(milliseconds: 60),
              textStyle: const TextStyle(color: Colors.white70, fontSize: 13, fontStyle: FontStyle.italic)),
          FadeAnimatedText(i18n.bienvenue,
              textStyle: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    ),
  ]);
}

class _Champ extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icone;
  final TextInputType type;
  final bool obscure;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  const _Champ({required this.label, required this.controller, required this.icone,
    this.type = TextInputType.text, this.obscure = false, this.suffixIcon, this.validator});

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: type,
    obscureText: obscure,
    textInputAction: TextInputAction.next,
    validator: validator,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icone, size: 20, color: Colors.grey.shade500),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.grey.shade50,
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
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.2),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      // Fulfulde (ff) : hors lancement (décision 03/11/2026) — non proposé
      children: AuthLang.values.where((l) => l != AuthLang.ff).map((l) {
        final actif = l == lang;
        final label = switch (l) { AuthLang.fr => '🇫🇷', AuthLang.en => '🇬🇧', AuthLang.ff => '🟡' };
        return GestureDetector(
          onTap: () => onChange(l),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: actif ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(label, style: TextStyle(fontSize: actif ? 16 : 14)),
          ),
        );
      }).toList(),
    ),
  );
}
