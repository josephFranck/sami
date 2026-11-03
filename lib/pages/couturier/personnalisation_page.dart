import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sami/models/couture.dart';
import 'package:sami/models/couture_options.dart';
import 'package:sami/utils/prix_fcfa.dart';

const _kPrimary = Color(0xFF6A1B9A);
const _kAccent = Color(0xFFFF8F00);

/// Page de personnalisation d'une commande couturier
/// Affiche les options du modèle + calculateur prix temps réel
class PersonnalisationPage extends StatefulWidget {
  final ModeleCoutureComplet modele;
  final Langue langue;
  final AbonnementCouturier abonnementCouturier;
  final ModeRencontre modeRencontre;
  final double fraisDeplacement;

  const PersonnalisationPage({
    super.key,
    required this.modele,
    required this.langue,
    this.abonnementCouturier = const AbonnementCouturier(
      type: TypeAbonnementCouturier.gratuit,
      nom: 'Standard',
      prixMensuel: 0,
      tauxCommission: 12,
      limiteModeles: 3,
      avantages: [],
    ),
    required this.modeRencontre,
    this.fraisDeplacement = 0,
  });

  @override
  State<PersonnalisationPage> createState() => _PersonnalisationPageState();
}

class _PersonnalisationPageState extends State<PersonnalisationPage> {
  // Choix actuels : optionId → PersonnalisationChoisie
  final Map<String, PersonnalisationChoisie> _choix = {};
  // Contrôleurs pour les champs texte libre
  final Map<String, TextEditingController> _textCtrl = {};

  @override
  void initState() {
    super.initState();
    // Pré-remplir avec les valeurs par défaut
    for (final opt in widget.modele.options) {
      if (opt.valeurDefaut != null) {
        _appliquerChoix(opt, opt.valeurDefaut);
      }
      if (opt.typeValeur == TypeValeurOption.texte_libre) {
        _textCtrl[opt.id] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    for (final c in _textCtrl.values) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final decomp = DecompositionCommandeCouturier.calculer(
      prixBase: widget.modele.base.prixBase,
      personnalisations: _choix.values.toList(),
      fraisDeplacement: widget.fraisDeplacement,
      abonnement: widget.abonnementCouturier,
    );

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(_t('Personnaliser', 'Customize', 'Sosnu')),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Résumé prix sticky
          _BarrePrix(decomp: decomp, langue: widget.langue),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                // Options gratuites
                if (widget.modele.optionsGratuites.isNotEmpty) ...[
                  _TitreSection(
                    titre: _t('Options incluses', 'Included options', 'Ko welaa yoɓde'),
                    icone: Icons.check_circle_outline,
                    couleur: Colors.green,
                  ),
                  const SizedBox(height: 8),
                  ...widget.modele.optionsGratuites.map((opt) => _CarteOption(
                    option: opt,
                    langue: widget.langue,
                    choixActuel: _choix[opt.id],
                    textCtrl: _textCtrl[opt.id],
                    onChoix: (valeur) => setState(() => _appliquerChoix(opt, valeur)),
                    gratuit: true,
                  )),
                  const SizedBox(height: 16),
                ],

                // Options payantes
                if (widget.modele.optionsPayantes.isNotEmpty) ...[
                  _TitreSection(
                    titre: _t('Options payantes', 'Paid options', 'Ko yoɓetee'),
                    icone: Icons.add_circle_outline,
                    couleur: _kPrimary,
                  ),
                  const SizedBox(height: 8),
                  ...widget.modele.optionsPayantes.map((opt) => _CarteOption(
                    option: opt,
                    langue: widget.langue,
                    choixActuel: _choix[opt.id],
                    textCtrl: _textCtrl[opt.id],
                    onChoix: (valeur) => setState(() => _appliquerChoix(opt, valeur)),
                    gratuit: false,
                  )),
                  const SizedBox(height: 16),
                ],

                // Note libre du client
                _SectionNoteLibre(langue: widget.langue),

                const SizedBox(height: 16),

                // Détail des coûts
                _DetailCouts(decomp: decomp, langue: widget.langue),

                const SizedBox(height: 80),
              ],
            ),
          ),

          // Bouton confirmer
          _BoutonConfirmer(
            decomp: decomp,
            langue: widget.langue,
            estValide: _estValide,
            onConfirmer: () => Navigator.pop(context, {
              'personnalisations': _choix.values.toList(),
              'decomposition': decomp,
            }),
          ),
        ],
      ),
    );
  }

  void _appliquerChoix(OptionPersonnalisation opt, dynamic valeur) {
    double surplus = 0;

    switch (opt.typeValeur) {
      case TypeValeurOption.choix:
        final choix = opt.choix.firstWhere(
          (c) => c.id == valeur,
          orElse: () => opt.choix.first,
        );
        surplus = opt.estGratuit ? 0 : choix.surplusPrix;
        _choix[opt.id] = PersonnalisationChoisie(
          optionId: opt.id,
          choixId: valeur as String?,
          surplusPrix: surplus,
        );

      case TypeValeurOption.oui_non:
        surplus = (valeur == true && !opt.estGratuit) ? opt.prixFixe : 0;
        _choix[opt.id] = PersonnalisationChoisie(
          optionId: opt.id,
          valeurBool: valeur as bool?,
          surplusPrix: surplus,
        );

      case TypeValeurOption.texte_libre:
        surplus = opt.estGratuit ? 0 : opt.prixFixe;
        _choix[opt.id] = PersonnalisationChoisie(
          optionId: opt.id,
          valeurTexte: valeur as String?,
          surplusPrix: (valeur as String?)?.isNotEmpty == true ? surplus : 0,
        );

      case TypeValeurOption.nombre:
        surplus = opt.estGratuit ? 0 : opt.prixFixe * (valeur as int? ?? 0);
        _choix[opt.id] = PersonnalisationChoisie(
          optionId: opt.id,
          valeurNombre: valeur as int?,
          surplusPrix: surplus,
        );

      case TypeValeurOption.couleur_hex:
        _choix[opt.id] = PersonnalisationChoisie(
          optionId: opt.id,
          valeurCouleur: valeur as String?,
          surplusPrix: 0,
        );
    }
  }

  bool get _estValide {
    for (final opt in widget.modele.options.where((o) => o.obligatoire)) {
      if (!_choix.containsKey(opt.id)) return false;
      final c = _choix[opt.id]!;
      if (opt.typeValeur == TypeValeurOption.choix && c.choixId == null) return false;
    }
    return true;
  }

  String _t(String fr, String en, String ff) => switch (widget.langue) {
    Langue.fr => fr,
    Langue.en => en,
    Langue.ff => ff,
  };
}

// ─── Barre prix sticky ────────────────────────────────────────────────────────

class _BarrePrix extends StatelessWidget {
  final DecompositionCommandeCouturier decomp;
  final Langue langue;
  const _BarrePrix({required this.decomp, required this.langue});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kPrimary,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  langue == Langue.fr ? 'Prix total' : langue == Langue.en ? 'Total price' : 'Ƴellitaari',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                Text(
                  decomp.prixFinalFmt,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          if (decomp.totalOptions > 0)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  langue == Langue.fr ? 'Base' : 'Base',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
                Text(
                  PrixFCFA.formater(decomp.prixBase),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  '+ ${PrixFCFA.formater(decomp.totalOptions)}',
                  style: const TextStyle(color: _kAccent, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ─── Carte d'une option ───────────────────────────────────────────────────────

class _CarteOption extends StatelessWidget {
  final OptionPersonnalisation option;
  final Langue langue;
  final PersonnalisationChoisie? choixActuel;
  final TextEditingController? textCtrl;
  final ValueChanged<dynamic> onChoix;
  final bool gratuit;

  const _CarteOption({
    required this.option,
    required this.langue,
    required this.choixActuel,
    this.textCtrl,
    required this.onChoix,
    required this.gratuit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête option
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            option.label(langue),
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          if (option.obligatoire) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                langue == Langue.fr ? 'Requis' : langue == Langue.en ? 'Required' : 'Haɗɗiiɗo',
                                style: TextStyle(color: Colors.red.shade700, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (option.description(langue).isNotEmpty)
                        Text(
                          option.description(langue),
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
                if (!gratuit && option.prixMax > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _kPrimary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      option.prixMin == option.prixMax
                          ? '+${PrixFCFA.formater(option.prixMax)}'
                          : '+${PrixFCFA.formater(option.prixMin)}–${PrixFCFA.formater(option.prixMax)}',
                      style: const TextStyle(color: _kPrimary, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  )
                else if (gratuit)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      langue == Langue.fr ? 'Inclus' : langue == Langue.en ? 'Included' : 'Welaa',
                      style: TextStyle(color: Colors.green.shade700, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Saisie selon le type
          Padding(
            padding: const EdgeInsets.all(12),
            child: _buildInput(),
          ),
        ],
      ),
    );
  }

  Widget _buildInput() {
    switch (option.typeValeur) {
      case TypeValeurOption.choix:
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: option.choix.map((choix) {
            final isSelected = choixActuel?.choixId == choix.id;
            return GestureDetector(
              onTap: () => onChoix(choix.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected ? _kPrimary : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? _kPrimary : Colors.grey.shade300,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      choix.label(langue),
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    if (!gratuit && choix.surplusPrix > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '+${PrixFCFA.formaterSansDevise(choix.surplusPrix)}',
                        style: TextStyle(
                          color: isSelected ? Colors.white70 : _kAccent,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        );

      case TypeValeurOption.oui_non:
        final valeur = choixActuel?.valeurBool ?? false;
        return Row(
          children: [
            Switch(
              value: valeur,
              onChanged: onChoix,
              activeColor: _kPrimary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                valeur
                    ? (langue == Langue.fr ? 'Oui' : langue == Langue.en ? 'Yes' : 'Eey')
                    : (langue == Langue.fr ? 'Non' : langue == Langue.en ? 'No' : 'Alaa'),
                style: TextStyle(
                  color: valeur ? _kPrimary : Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (!gratuit && option.prixFixe > 0 && valeur)
              Text(
                '+${PrixFCFA.formater(option.prixFixe)}',
                style: const TextStyle(color: _kAccent, fontWeight: FontWeight.bold),
              ),
          ],
        );

      case TypeValeurOption.texte_libre:
        return TextField(
          controller: textCtrl,
          onChanged: onChoix,
          maxLength: 50,
          decoration: InputDecoration(
            hintText: langue == Langue.fr
                ? 'Entrez votre texte...'
                : langue == Langue.en
                    ? 'Enter your text...'
                    : 'Ƴeeto maɗɗaa...',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kPrimary, width: 1.5),
            ),
            counterText: '',
          ),
        );

      case TypeValeurOption.nombre:
        final val = choixActuel?.valeurNombre ?? (option.min ?? 0);
        return Row(
          children: [
            _BoutonQte(
              icone: Icons.remove,
              onTap: val > (option.min ?? 0) ? () => onChoix(val - 1) : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('$val', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            _BoutonQte(
              icone: Icons.add,
              onTap: val < (option.max ?? 99) ? () => onChoix(val + 1) : null,
            ),
            const Spacer(),
            if (!gratuit && option.prixFixe > 0 && val > 0)
              Text(
                '+${PrixFCFA.formater(option.prixFixe * val)}',
                style: const TextStyle(color: _kAccent, fontWeight: FontWeight.bold),
              ),
          ],
        );

      case TypeValeurOption.couleur_hex:
        return const Text('Sélecteur de couleur — à implémenter avec flutter_colorpicker');
    }
  }

}

class _BoutonQte extends StatelessWidget {
  final IconData icone;
  final VoidCallback? onTap;
  const _BoutonQte({required this.icone, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        border: Border.all(color: onTap != null ? Colors.grey.shade400 : Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
        color: onTap != null ? Colors.white : Colors.grey.shade50,
      ),
      child: Icon(icone, size: 16, color: onTap != null ? Colors.black87 : Colors.grey.shade300),
    ),
  );
}

// ─── Section note libre ───────────────────────────────────────────────────────

class _SectionNoteLibre extends StatelessWidget {
  final Langue langue;
  const _SectionNoteLibre({required this.langue});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.edit_note, color: _kPrimary, size: 18),
            const SizedBox(width: 6),
            Text(
              langue == Langue.fr ? 'Demandes spéciales' : langue == Langue.en ? 'Special requests' : 'Ko haɓɓii fof',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          maxLines: 3,
          maxLength: 300,
          decoration: InputDecoration(
            hintText: langue == Langue.fr
                ? 'Ex: tissu doublé au niveau des genoux, coutures renforcées...'
                : langue == Langue.en
                    ? 'E.g.: double-lined at knees, reinforced seams...'
                    : 'Misal: ɗanngu ɗiɗum e gite...',
            hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kPrimary, width: 1.5),
            ),
            counterStyle: const TextStyle(fontSize: 10),
          ),
        ),
      ],
    ),
  );
}

// ─── Détail des coûts ─────────────────────────────────────────────────────────

class _DetailCouts extends StatelessWidget {
  final DecompositionCommandeCouturier decomp;
  final Langue langue;
  const _DetailCouts({required this.decomp, required this.langue});

  @override
  Widget build(BuildContext context) {
    final lblDetail = langue == Langue.fr ? 'Détail du prix' : langue == Langue.en ? 'Price breakdown' : 'Winndude ƴellitaari';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(lblDetail, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 10),
          _ligne(langue == Langue.fr ? 'Confection de base' : 'Base tailoring', PrixFCFA.formater(decomp.prixBase)),
          if (decomp.totalOptions > 0)
            _ligne(langue == Langue.fr ? 'Options choisies' : 'Selected options', '+${PrixFCFA.formater(decomp.totalOptions)}', couleur: _kAccent),
          if (decomp.fraisDeplacement > 0)
            _ligne(langue == Langue.fr ? 'Frais de déplacement' : 'Travel fees', '+${PrixFCFA.formater(decomp.fraisDeplacement)}'),
          const Divider(height: 16),
          _ligne(
            langue == Langue.fr ? 'Prix final' : 'Final price',
            decomp.prixFinalFmt,
            bold: true,
            couleur: _kPrimary,
          ),
        ],
      ),
    );
  }

  Widget _ligne(String label, String valeur, {bool bold = false, Color? couleur}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: bold ? Colors.black87 : Colors.grey, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        Text(valeur, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: couleur ?? Colors.black87)),
      ],
    ),
  );
}

// ─── Bouton confirmer ─────────────────────────────────────────────────────────

class _BoutonConfirmer extends StatelessWidget {
  final DecompositionCommandeCouturier decomp;
  final Langue langue;
  final bool estValide;
  final VoidCallback onConfirmer;

  const _BoutonConfirmer({
    required this.decomp,
    required this.langue,
    required this.estValide,
    required this.onConfirmer,
  });

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: EdgeInsets.only(
      left: 16, right: 16, top: 10,
      bottom: MediaQuery.of(context).padding.bottom + 10,
    ),
    child: SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: estValide ? onConfirmer : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kPrimary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade200,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          '${langue == Langue.fr ? 'Confirmer' : langue == Langue.en ? 'Confirm' : 'Jaɓɓo'} · ${decomp.prixFinalFmt}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );
}

// ─── Titre section ────────────────────────────────────────────────────────────

class _TitreSection extends StatelessWidget {
  final String titre;
  final IconData icone;
  final Color couleur;
  const _TitreSection({required this.titre, required this.icone, required this.couleur});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icone, color: couleur, size: 16),
      const SizedBox(width: 6),
      Text(titre, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: couleur)),
    ],
  );
}
