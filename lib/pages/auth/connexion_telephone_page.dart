import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sami/services/parametres_service.dart';
import 'package:sami/l10n/tr.dart';

const _kPrimary = Color(0xFF6A1B9A);

/// CONNEXION PAR TÉLÉPHONE — SMS (fournisseur Firebase natif) ou WhatsApp
/// (code envoyé par la Cloud Function authWhatsappEnvoyer, vérifié par
/// authWhatsappVerifier → jeton personnalisé). Décision du 03/11/2026 :
/// « téléphone + email, et WhatsApp, Facebook, Telegram ou autre ».
///
/// Un numéro = un compte : si c'est une première connexion, l'accueil
/// (_AuthGate) envoie vers « Compléter mon profil » (nom, quartier, CGU).
enum CanalCode { sms, whatsapp }

class ConnexionTelephonePage extends StatefulWidget {
  final CanalCode canalInitial;
  const ConnexionTelephonePage({super.key, this.canalInitial = CanalCode.sms});

  /// Quels canaux l'exploitant a activés (console : app_config/parametres
  /// `connexionSmsActive`, `connexionWhatsappActive`).
  static Future<List<CanalCode>> canauxActifs() async {
    final sms = await ParametresService.connexionSmsActive();
    final wa = await ParametresService.connexionWhatsappActive();
    return [if (sms) CanalCode.sms, if (wa) CanalCode.whatsapp];
  }

  @override
  State<ConnexionTelephonePage> createState() => _ConnexionTelephonePageState();
}

class _ConnexionTelephonePageState extends State<ConnexionTelephonePage> {
  late CanalCode _canal = widget.canalInitial;
  final _telCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _codeEnvoye = false;
  bool _enCours = false;
  String? _erreur;
  String? _verificationId; // SMS
  int? _resendToken;

  String get _telephone => '+237${_telCtrl.text.trim().replaceAll(RegExp(r'\D'), '')}';
  bool get _telValide => RegExp(r'^\+237[26]\d{8}$').hasMatch(_telephone);

  @override
  void dispose() {
    _telCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    if (!_telValide) {
      setState(() => _erreur = 'Entrez un numéro camerounais à 9 chiffres (6XX XX XX XX)');
      return;
    }
    setState(() { _enCours = true; _erreur = null; });
    try {
      if (_canal == CanalCode.sms) {
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: _telephone,
          forceResendingToken: _resendToken,
          timeout: const Duration(seconds: 60),
          verificationCompleted: (cred) async {
            // Android : code lu automatiquement
            try {
              await FirebaseAuth.instance.signInWithCredential(cred);
              if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            } catch (_) {}
          },
          verificationFailed: (e) {
            if (mounted) setState(() { _enCours = false; _erreur = _messageErreur(e.code); });
          },
          codeSent: (id, token) {
            if (mounted) setState(() { _verificationId = id; _resendToken = token; _codeEnvoye = true; _enCours = false; });
          },
          codeAutoRetrievalTimeout: (id) { _verificationId = id; },
        );
      } else {
        await FirebaseFunctions.instanceFor(region: 'europe-west1')
            .httpsCallable('authWhatsappEnvoyer')
            .call({'telephone': _telephone});
        if (mounted) setState(() { _codeEnvoye = true; _enCours = false; });
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() { _enCours = false; _erreur = e.message ?? e.code; });
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() { _enCours = false; _erreur = _messageErreur(e.code); });
    } catch (e) {
      if (mounted) setState(() { _enCours = false; _erreur = 'Envoi impossible : $e'; });
    }
  }

  Future<void> _verifier() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _erreur = 'Entrez le code à 6 chiffres reçu');
      return;
    }
    setState(() { _enCours = true; _erreur = null; });
    try {
      if (_canal == CanalCode.sms) {
        final id = _verificationId;
        if (id == null) throw FirebaseAuthException(code: 'session-expired');
        await FirebaseAuth.instance.signInWithCredential(
            PhoneAuthProvider.credential(verificationId: id, smsCode: code));
      } else {
        final r = await FirebaseFunctions.instanceFor(region: 'europe-west1')
            .httpsCallable('authWhatsappVerifier')
            .call<Map<String, dynamic>>({'telephone': _telephone, 'code': code});
        final jeton = Map<String, dynamic>.from(r.data)['token'] as String?;
        if (jeton == null) throw Exception('jeton absent');
        await FirebaseAuth.instance.signInWithCustomToken(jeton);
      }
      // _AuthGate (main.dart) prend le relais : accueil, ou « Compléter mon
      // profil » si c'est un nouveau compte.
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() { _enCours = false; _erreur = e.message ?? e.code; });
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() { _enCours = false; _erreur = _messageErreur(e.code); });
    } catch (e) {
      if (mounted) setState(() { _enCours = false; _erreur = 'Vérification impossible : $e'; });
    }
  }

  String _messageErreur(String code) => switch (code) {
        'invalid-verification-code' => Tr.s.codeIncorrect,
        'session-expired' || 'code-expired' => Tr.s.codeExpireRenvoyezCode,
        'too-many-requests' => Tr.s.tropTentativesReessayezPlusTard,
        'invalid-phone-number' => Tr.s.numeroTelephoneInvalide,
        'quota-exceeded' => Tr.s.serviceSmsMomentanementSatureEssayez,
        'network-request-failed' => Tr.s.pasConnexionVerifiezVotreReseau,
        _ => Tr.s.erreurConnexion(code),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(Tr.s.connexionParTelephone),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FutureBuilder<List<CanalCode>>(
            future: ConnexionTelephonePage.canauxActifs(),
            builder: (_, snap) {
              final canaux = snap.data ?? [widget.canalInitial];
              if (canaux.length < 2) return const SizedBox.shrink();
              return SegmentedButton<CanalCode>(
                segments: const [
                  ButtonSegment(value: CanalCode.sms, icon: Icon(Icons.sms_outlined), label: Text('SMS')),
                  ButtonSegment(value: CanalCode.whatsapp, icon: Icon(Icons.chat_outlined), label: Text('WhatsApp')),
                ],
                selected: {_canal},
                onSelectionChanged: _codeEnvoye ? null : (s) => setState(() => _canal = s.first),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            _codeEnvoye
                ? Tr.s.codeEnvoye(_telephone)
                : (_canal == CanalCode.sms
                    ? Tr.s.vousRecevrezCodeParSms
                    : Tr.s.vousRecevrezCodeSurWhatsapp),
            style: const TextStyle(fontSize: 13.5, color: Colors.black87),
          ),
          const SizedBox(height: 12),
          if (!_codeEnvoye)
            TextField(
              controller: _telCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
              decoration: InputDecoration(
                labelText: Tr.s.numeroTelephone,
                prefixText: '+237 ',
                hintText: '6XX XX XX XX',
                border: OutlineInputBorder(),
              ),
            )
          else
            TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              autofocus: true,
              decoration: InputDecoration(
                labelText: Tr.s.code6Chiffres,
                border: OutlineInputBorder(),
              ),
            ),
          if (_erreur != null) ...[
            const SizedBox(height: 10),
            Text(_erreur!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white),
              onPressed: _enCours ? null : (_codeEnvoye ? _verifier : _envoyer),
              child: _enCours
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(_codeEnvoye ? Tr.s.verifierCode : Tr.s.recevoirCode),
            ),
          ),
          if (_codeEnvoye) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _enCours ? null : () => setState(() { _codeEnvoye = false; _codeCtrl.clear(); _erreur = null; }),
              child: Text(Tr.s.changerNumeroOuRenvoyerCode),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            Tr.s.numeroCompteVotreNumeroSert,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
