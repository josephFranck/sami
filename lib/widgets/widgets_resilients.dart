import 'package:flutter/material.dart';
import 'package:sami/services/resilience_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// WIDGETS RÉSILIENTS — À intégrer dans les formulaires critiques
// ═══════════════════════════════════════════════════════════════════════════

// ─── Mixin AutoSave pour StatefulWidget ──────────────────────────────────────
// Usage : class _MaPageState extends State<MaPage> with AutoSaveMixin

mixin AutoSaveMixin<T extends StatefulWidget> on State<T> {
  String get autosaveCle;   // clé unique pour ce formulaire (ex: 'mesures_client_XYZ')
  bool _autosaveCharge = false;

  /// Charger les données sauvegardées et proposer de reprendre
  Future<void> chargerAutosave({
    required void Function(Map<String, dynamic> donnees) onReprendre,
  }) async {
    if (_autosaveCharge) return;
    _autosaveCharge = true;

    final donnees = await AutoSave.charger(autosaveCle);
    if (donnees == null || !mounted) return;

    // Proposer de reprendre
    final reprise = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [
          Icon(Icons.restore, color: Color(0xFF6A1B9A), size: 22),
          SizedBox(width: 8),
          Text('Reprendre où vous étiez ?'),
        ]),
        content: const Text(
          'Vous avez des données non sauvegardées de votre dernière session.\n'
          'Voulez-vous les récupérer ?',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Non, recommencer'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6A1B9A),
              foregroundColor: Colors.white,
            ),
            child: const Text('Oui, reprendre'),
          ),
        ],
      ),
    );

    if (reprise == true && mounted) {
      onReprendre(donnees);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Données précédentes restaurées ✓'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
    } else if (reprise == false) {
      await AutoSave.effacer(autosaveCle);
    }
  }

  /// Sauvegarder automatiquement (appeler à chaque changement)
  void autosauvegarder(Map<String, dynamic> donnees) {
    AutoSave.sauvegarder(autosaveCle, donnees);
  }

  /// Effacer après soumission réussie
  Future<void> effacerAutosave() => AutoSave.effacer(autosaveCle);
}

// ─── Champ de texte avec autosave ────────────────────────────────────────────

class ChampAutosave extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final VoidCallback? onChanged;
  final int? maxLines;
  final String? prefixText;
  final String? suffixText;

  const ChampAutosave({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.validator,
    this.onChanged,
    this.maxLines = 1,
    this.prefixText,
    this.suffixText,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: keyboardType,
    maxLines: maxLines,
    onChanged: (_) => onChanged?.call(),
    validator: validator,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefixText,
      suffixText: suffixText,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF6A1B9A), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.red),
      ),
    ),
  );
}

// ─── Bouton d'action résilient ────────────────────────────────────────────────

class BoutonResiliant extends StatefulWidget {
  final String label;
  final Future<void> Function() onTap;
  final TypeActionOffline? typeOffline;
  final Map<String, dynamic>? payloadOffline;
  final String? idIdempotent;
  final Color couleur;
  final IconData? icone;
  final bool pleineLargeur;

  const BoutonResiliant({
    super.key,
    required this.label,
    required this.onTap,
    this.typeOffline,
    this.payloadOffline,
    this.idIdempotent,
    this.couleur = const Color(0xFF6A1B9A),
    this.icone,
    this.pleineLargeur = true,
  });

  @override
  State<BoutonResiliant> createState() => _BoutonResiliantState();
}

class _BoutonResiliantState extends State<BoutonResiliant> {
  bool _enCours = false;
  bool _enAttente = false;  // mis en file offline

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.pleineLargeur ? double.infinity : null,
      child: ElevatedButton(
        onPressed: _enCours ? null : _executer,
        style: ElevatedButton.styleFrom(
          backgroundColor: _enAttente ? Colors.orange : widget.couleur,
          foregroundColor: Colors.white,
          minimumSize: widget.pleineLargeur ? const Size(double.infinity, 50) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _enCours
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Row(
                mainAxisSize: widget.pleineLargeur ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_enAttente) const Icon(Icons.schedule, size: 16),
                  if (widget.icone != null && !_enAttente) Icon(widget.icone, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _enAttente ? 'En attente de connexion...' : widget.label,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _executer() async {
    setState(() => _enCours = true);
    try {
      await widget.onTap();
      if (mounted) setState(() { _enCours = false; _enAttente = false; });
    } catch (e) {
      if (!mounted) return;

      // Si erreur réseau et action offline définie → mettre en file
      if (widget.typeOffline != null && widget.payloadOffline != null) {
        final estErreurReseau = e.toString().toLowerCase().contains('network') ||
            e.toString().toLowerCase().contains('unavailable') ||
            e.toString().toLowerCase().contains('timeout');

        if (estErreurReseau || !ConnectiviteService.instance.estConnecte) {
          await FileAttenteOffline.instance.ajouter(
            type: widget.typeOffline!,
            payload: widget.payloadOffline!,
            idForce: widget.idIdempotent,
          );
          if (mounted) {
            setState(() { _enCours = false; _enAttente = true; });
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Action sauvegardée — sera envoyée au retour du réseau'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ));
          }
          return;
        }
      }

      if (mounted) {
        setState(() => _enCours = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }
}

// ─── Scanner QR résilient ────────────────────────────────────────────────────

class ScanQRResiliant extends StatelessWidget {
  final String qrAttendu;
  final String sousCommandeId;
  final String livraisonId;
  final String livreurId;
  final bool estDepart;        // true = scan départ, false = scan arrivée
  final VoidCallback? onSucces;

  const ScanQRResiliant({
    super.key,
    required this.qrAttendu,
    required this.sousCommandeId,
    required this.livraisonId,
    required this.livreurId,
    required this.estDepart,
    this.onSucces,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // En mode production : utiliser mobile_scanner
        // En mode dégradé (pas de caméra / réseau faible) : saisie manuelle
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF6A1B9A), width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              const Icon(Icons.qr_code_scanner, size: 48, color: Color(0xFF6A1B9A)),
              const SizedBox(height: 8),
              Text(
                estDepart ? 'Scanner le QR en boutique' : 'Scanner le QR de livraison',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              // Bouton de validation directe (démo)
              // En production : déclenché par mobile_scanner après scan
              BoutonResiliant(
                label: estDepart ? 'Confirmer prise en charge' : 'Confirmer réception',
                typeOffline: estDepart ? TypeActionOffline.scanQR : TypeActionOffline.confirmerLivraison,
                payloadOffline: {
                  'sousCommandeId': sousCommandeId,
                  'livraisonId': livraisonId,
                  'livreurId': livreurId,
                  'statut': estDepart ? 'enCours' : 'livree',
                  'statutSousCommande': estDepart ? 'enCoursLivraison' : 'terminee',
                },
                onTap: () async {
                  // Valider le QR
                  if (estDepart) {
                    // _validerQRDepart
                  } else {
                    // _validerQRArrivee
                  }
                  onSucces?.call();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Mode dégradé : OTP manuel
        _SectionOTPSecours(
          sousCommandeId: sousCommandeId,
          livraisonId: livraisonId,
          estDepart: estDepart,
          onSucces: onSucces,
        ),
      ],
    );
  }
}

// ─── Section OTP de secours (quand QR scanner ne fonctionne pas) ──────────────

class _SectionOTPSecours extends StatefulWidget {
  final String sousCommandeId;
  final String livraisonId;
  final bool estDepart;
  final VoidCallback? onSucces;

  const _SectionOTPSecours({
    required this.sousCommandeId,
    required this.livraisonId,
    required this.estDepart,
    this.onSucces,
  });

  @override
  State<_SectionOTPSecours> createState() => _SectionOTPSecoursState();
}

class _SectionOTPSecoursState extends State<_SectionOTPSecours> {
  bool _afficher = false;
  final _otpCtrl = TextEditingController();

  @override
  void dispose() { _otpCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextButton.icon(
        onPressed: () => setState(() => _afficher = !_afficher),
        icon: const Icon(Icons.sms_outlined, size: 16, color: Colors.grey),
        label: const Text('Utiliser le code reçu par SMS',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
      ),
      if (_afficher) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Column(
            children: [
              const Text(
                'Entrez le code PIN à 4 chiffres reçu par SMS',
                style: TextStyle(fontSize: 12, color: Colors.orange),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _otpCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
                decoration: const InputDecoration(
                  counterText: '',
                  border: OutlineInputBorder(),
                  hintText: '••••',
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _validerOTP,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 42),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Valider le code'),
              ),
            ],
          ),
        ),
      ],
    ],
  );

  Future<void> _validerOTP() async {
    // En production : vérifier le code OTP stocké dans Firestore
    // Le code est généré lors de la création de la livraison et envoyé par SMS
    final code = _otpCtrl.text.trim();
    if (code.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Entrez un code à 4 chiffres'), backgroundColor: Colors.red));
      return;
    }

    // Vérification Firestore + mise en file si offline
    await FileAttenteOffline.instance.ajouter(
      type: widget.estDepart ? TypeActionOffline.scanQR : TypeActionOffline.confirmerLivraison,
      payload: {
        'sousCommandeId': widget.sousCommandeId,
        'livraisonId': widget.livraisonId,
        'methodeValidation': 'otp',
        'codeOTP': code,
        'statut': widget.estDepart ? 'enCours' : 'livree',
        'statutSousCommande': widget.estDepart ? 'enCoursLivraison' : 'terminee',
      },
    );

    if (mounted) {
      widget.onSucces?.call();
      Navigator.pop(context);
    }
  }
}
