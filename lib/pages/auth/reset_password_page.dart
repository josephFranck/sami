import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sami/utils/auth_i18n.dart';
import 'package:sami/services/langue_service.dart';

class ResetPasswordPage extends StatefulWidget {
  final AuthLang lang;
  const ResetPasswordPage({super.key, this.lang = AuthLang.fr});
  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey    = GlobalKey<FormState>();
  final _emailCtrl  = TextEditingController();
  late AuthLang _lang;
  late AuthI18n _i18n;
  bool _enCours = false;
  bool _envoye  = false;
  String? _erreur;

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
  void dispose() { _emailCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Image.asset('lib/assets/images/pagne_back.jpg',
            fit: BoxFit.cover, height: double.infinity, width: double.infinity),
        Container(color: Colors.black.withOpacity(0.45)),
        SafeArea(child: Column(children: [
          // Barre haut
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context)),
              const Spacer(),
              _SelecteurLang(lang: _lang, onChange: _changerLang),
            ]),
          ),
          Expanded(child: Center(child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(children: [
              // Icône
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(color: const Color(0xFF6A1B9A).withOpacity(0.15),
                    shape: BoxShape.circle, border: Border.all(color: Colors.white30, width: 2)),
                child: const Icon(Icons.lock_reset_outlined, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 20),
              Text(_i18n.resetTitre,
                  style: const TextStyle(color: Colors.white, fontSize: 24,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black45, blurRadius: 6)])),
              const SizedBox(height: 28),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.97),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: const Offset(0, 8))],
                ),
                padding: const EdgeInsets.all(24),
                child: _envoye ? _buildSucces() : _buildFormulaire(),
              ),
            ]),
          ))),
        ])),
      ]),
    );
  }

  Widget _buildFormulaire() => Form(
    key: _formKey,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(_i18n.resetDesc,
          style: const TextStyle(color: Colors.grey, fontSize: 14, height: 1.5)),
      const SizedBox(height: 24),
      TextFormField(
        controller: _emailCtrl,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _envoyer(),
        validator: (v) {
          if (v?.isEmpty ?? true) return _i18n.champRequis;
          if (!(v?.contains('@') ?? false)) return _i18n.emailInvalide;
          return null;
        },
        decoration: InputDecoration(
          labelText: _i18n.email,
          prefixIcon: Icon(Icons.email_outlined, size: 20, color: Colors.grey.shade500),
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
      ),
      if (_erreur != null) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200)),
          child: Row(children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(_erreur!, style: const TextStyle(color: Colors.red, fontSize: 13))),
          ]),
        ),
      ],
      const SizedBox(height: 20),
      SizedBox(
        height: 50,
        child: ElevatedButton(
          onPressed: _enCours ? null : _envoyer,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6A1B9A),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _enCours
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Text(_i18n.envoyer,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
      const SizedBox(height: 14),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(_i18n.retourConnexion,
            style: const TextStyle(color: Color(0xFF6A1B9A), fontSize: 13)),
      ),
    ]),
  );

  Widget _buildSucces() => Column(children: [
    TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (_, v, child) => Transform.scale(scale: v, child: child),
      child: Container(
        width: 64, height: 64,
        decoration: const BoxDecoration(color: Color(0xFF1D9E75), shape: BoxShape.circle),
        child: const Icon(Icons.check, color: Colors.white, size: 36),
      ),
    ),
    const SizedBox(height: 16),
    Text(_i18n.resetEnvoye,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1D9E75)),
        textAlign: TextAlign.center),
    const SizedBox(height: 8),
    Text(_emailCtrl.text, style: const TextStyle(color: Colors.grey, fontSize: 13)),
    const SizedBox(height: 24),
    SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back, size: 18),
        label: Text(_i18n.retourConnexion),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF6A1B9A),
          side: const BorderSide(color: Color(0xFF6A1B9A)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ),
  ]);

  Future<void> _envoyer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _enCours = true; _erreur = null; });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: _emailCtrl.text.trim());
      if (mounted) setState(() => _envoye = true);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _erreur = _i18n.erreurFirebase(e.code));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }
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
