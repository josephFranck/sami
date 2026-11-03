import 'package:flutter/material.dart';

/// Version des CGU acceptées — INCRÉMENTER à chaque modification de fond.
/// Stockée sur le compte (cguVersion) et sur chaque commande : c'est la
/// PREUVE du consentement exigée par l'art. 26 de la loi n° 2010/021.
const String kCguVersion = '2026-11-03';

/// ═══════════════════════════════════════════════════════════════════════
/// À COMPLÉTER AVANT LE LANCEMENT — identité légale de l'exploitant
/// (art. 30 loi n° 2010/021 : accès facile, direct et permanent).
/// Tant que la société n'est pas immatriculée, l'exploitant est une
/// personne physique : indiquer nom, prénoms, adresse, courriel, téléphone.
/// ═══════════════════════════════════════════════════════════════════════
const Map<String, String> kExploitant = {
  'nom': '[RAISON SOCIALE ou NOM ET PRÉNOMS DE L\'EXPLOITANT]',
  'forme': '[SARL / entreprise individuelle — à préciser]',
  'rccm': '[N° registre du commerce et du crédit mobilier — si immatriculé]',
  'niu': '[N° d\'identifiant unique (contribuable) — si assujetti]',
  'adresse': '[Adresse du siège — Garoua, Région du Nord, Cameroun]',
  'email': '[courriel de contact]',
  'telephone': '[téléphone de contact]',
  'dpo': '[contact protection des données — même adresse si pas de DPO]',
};

const _kPrimary = Color(0xFF6A1B9A);

/// Mentions légales · CGU · Politique de confidentialité.
/// Accessible SANS connexion (lisible avant l'inscription).
class MentionsLegalesPage extends StatelessWidget {
  final int ongletInitial; // 0 = mentions, 1 = CGU, 2 = confidentialité
  const MentionsLegalesPage({super.key, this.ongletInitial = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: ongletInitial.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Informations légales'),
          backgroundColor: _kPrimary,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Mentions'),
              Tab(text: 'CGU'),
              Tab(text: 'Données'),
            ],
          ),
        ),
        body: Column(children: [
          // Bandeau de prudence : ce texte est un cadre, pas un avis juridique
          Container(
            width: double.infinity,
            color: Colors.orange.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              'Version $kCguVersion — texte cadre à faire valider par un '
              'juriste avant publication.',
              style: TextStyle(fontSize: 11, color: Colors.orange.shade900),
            ),
          ),
          const Expanded(
            child: TabBarView(children: [
              _Mentions(),
              _Cgu(),
              _Confidentialite(),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─── helpers de mise en page ─────────────────────────────────────────────
class _Doc extends StatelessWidget {
  final List<Widget> children;
  const _Doc({required this.children});
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: children,
      );
}

Widget _h(String t) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(t,
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 14.5, color: _kPrimary)),
    );

Widget _p(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t, style: const TextStyle(fontSize: 13, height: 1.45)),
    );

Widget _ref(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t,
          style: TextStyle(
              fontSize: 11, color: Colors.grey.shade600,
              fontStyle: FontStyle.italic)),
    );

// ─── 1. MENTIONS LÉGALES (art. 30 & 31, loi n° 2010/021) ─────────────────
class _Mentions extends StatelessWidget {
  const _Mentions();
  @override
  Widget build(BuildContext context) => _Doc(children: [
        _h('Éditeur de l\'application PagneShop'),
        _p('${kExploitant['nom']}\n${kExploitant['forme']}\n'
            'Adresse : ${kExploitant['adresse']}\n'
            'Courriel : ${kExploitant['email']}\n'
            'Téléphone : ${kExploitant['telephone']}'),
        _p('Registre du commerce et du crédit mobilier : ${kExploitant['rccm']}\n'
            'Numéro d\'identifiant unique : ${kExploitant['niu']}'),
        _ref('Loi n° 2010/021 du 21 décembre 2010 régissant le commerce '
            'électronique au Cameroun, art. 30 (informations minimales) et '
            'art. 31 (prix clairs, taxes et frais de livraison précisés).'),
        _h('Hébergement et traitement des données'),
        _p('Les données de l\'application sont hébergées sur les services '
            'Google Firebase (Google LLC). Les serveurs peuvent être situés '
            'hors du Cameroun : voir l\'onglet « Données » pour les '
            'garanties et l\'autorisation requise.'),
        _h('Nature du service'),
        _p('PagneShop est une place de marché : elle met en relation des '
            'clients, des boutiques de pagnes, des couturiers et des livreurs '
            'indépendants. Les boutiques et couturiers sont les vendeurs des '
            'articles et prestations proposés ; PagneShop fournit la plateforme, '
            'le paiement et l\'organisation de la livraison.'),
        _h('Prix'),
        _p('Tous les prix sont affichés en francs CFA (XAF), toutes taxes '
            'comprises. Les frais de livraison sont indiqués séparément et '
            'avant la validation de la commande.'),
      ]);
}

// ─── 2. CGU (loi n° 2010/021 : art. 11, 12, 15, 17, 20, 21, 22, 26) ──────
class _Cgu extends StatelessWidget {
  const _Cgu();
  @override
  Widget build(BuildContext context) => _Doc(children: [
        _h('1. Objet et acceptation'),
        _p('Les présentes conditions régissent l\'utilisation de PagneShop. '
            'La création d\'un compte vaut acceptation de la version en '
            'vigueur ($kCguVersion). Le service est réservé aux personnes '
            'majeures (18 ans révolus).'),
        _h('2. Commande'),
        _p('Avant de valider, vous pouvez vérifier le détail de votre commande, '
            'son prix total, les frais de livraison et corriger toute erreur. '
            'Un accusé de réception vous est adressé dans l\'application dès '
            'la validation. Le contrat est conclu à l\'acceptation de la '
            'commande par la boutique.'),
        _ref('Art. 12 et 17 — vérification et confirmation ; accusé de '
            'réception sous 5 jours.'),
        _h('3. Prix, paiement'),
        _p('Les prix sont fermes au moment de la commande. Le paiement '
            's\'effectue par Mobile Money, par crédits PagneShop ou, pour les '
            'abonnés, en espèces à la livraison. Les crédits PagneShop sont un '
            'moyen de paiement interne à la plateforme : ils ne sont ni '
            'transférables à un tiers ni retirables en espèces, et sont '
            'remboursés sur le même support en cas d\'annulation.'),
        _h('4. Livraison'),
        _p('La livraison est assurée par des livreurs indépendants partenaires. '
            'La remise du colis est validée par le code de réception que vous '
            'présentez au livreur. Une signature peut être demandée en '
            'complément ; elle ne constitue pas une signature électronique '
            'certifiée au sens de la loi.'),
        _h('5. Droit de rétractation'),
        _p('Pour les pagnes et articles non personnalisés, vous disposez de '
            '15 jours à compter du lendemain de la réception pour vous '
            'rétracter, via la fonction « Demander un retour » de votre '
            'commande. Les frais de retour sont à votre charge. Le '
            'remboursement intervient dans les 15 jours suivant le retour, si '
            'l\'article n\'a pas été altéré.'),
        _p('EXCEPTION : les vêtements confectionnés sur mesure (service '
            '« Faire coudre ») sont réalisés selon vos caractéristiques '
            'personnalisées et ne peuvent faire l\'objet d\'une rétractation, '
            'sans préjudice de la garantie de conformité.'),
        _ref('Art. 20 (délai de 15 jours, remboursement, frais de retour), '
            'art. 21 (non-conformité ou retard), art. 22 (exclusion des '
            'produits confectionnés selon des caractéristiques personnalisées).'),
        _h('6. Non-conformité, retard'),
        _p('En cas d\'article non conforme ou de retard de livraison, vous '
            'pouvez demander la restitution dans les 15 jours suivant la '
            'livraison ; le remboursement intervient dans les 15 jours.'),
        _h('7. Avis et contenus'),
        _p('Les avis sont réservés aux clients ayant effectivement reçu la '
            'commande. Tout avis frauduleux, injurieux ou contraire à la loi '
            'peut être retiré. Vous conservez la responsabilité des contenus '
            '(photos, textes) que vous publiez.'),
        _h('8. Boutiques, couturiers, livreurs'),
        _p('Les partenaires professionnels sont des commerçants ou '
            'prestataires indépendants, liés à PagneShop par un contrat '
            'distinct (commissions, reversements, caution de livraison, '
            'règles de service). Ils sont responsables de la conformité des '
            'articles et prestations qu\'ils proposent.'),
        _h('9. Litiges — droit applicable'),
        _p('Les présentes sont soumises au droit camerounais. En cas de '
            'litige, une solution amiable est recherchée via le service '
            'client ; à défaut, les juridictions compétentes de Garoua '
            'pourront être saisies, sans préjudice des règles de compétence '
            'protectrices du consommateur.'),
        _ref('Loi-cadre n° 2011/012 du 6 mai 2011 portant protection du '
            'consommateur au Cameroun.'),
      ]);
}

// ─── 3. CONFIDENTIALITÉ (loi n° 2024/017 du 23 décembre 2024) ────────────
class _Confidentialite extends StatelessWidget {
  const _Confidentialite();
  @override
  Widget build(BuildContext context) => _Doc(children: [
        _h('Responsable du traitement'),
        _p('${kExploitant['nom']} — contact données personnelles : '
            '${kExploitant['dpo']}'),
        _ref('Loi n° 2024/017 du 23 décembre 2024 portant protection des '
            'données à caractère personnel, applicable depuis le 23 juin 2026.'),
        _h('Données collectées et finalités'),
        _p('• Identité et contact (nom, prénom, téléphone, courriel, quartier) : '
            'gestion du compte, des commandes et des livraisons.\n'
            '• Adresse et position GPS de livraison : acheminement du colis '
            '(uniquement lorsque vous la fixez sur la carte).\n'
            '• Mesures corporelles (profils de mesures) : confection sur mesure, '
            'transmises au seul couturier choisi.\n'
            '• Photos de preuve de livraison (colis, point de repère) et '
            'signature éventuelle : preuve de la remise, prévention des litiges.\n'
            '• Historique de commandes, points de fidélité, crédits : exécution '
            'du service et obligations comptables.\n'
            '• Pour les livreurs partenaires : pièce d\'identité (vérification), '
            'position pendant les courses (suivi de livraison pour le client).'),
        _h('Base du traitement'),
        _p('Votre consentement explicite, recueilli à l\'inscription, et '
            'l\'exécution du contrat (vos commandes). Chaque finalité facultative '
            '(messages promotionnels, position GPS) fait l\'objet d\'un '
            'consentement distinct, que vous pouvez retirer à tout moment.'),
        _h('Destinataires'),
        _p('Vos données ne sont communiquées qu\'aux partenaires nécessaires à '
            'votre commande : la boutique (articles), le couturier (mesures), '
            'le livreur (adresse, position, téléphone). Elles ne sont ni '
            'vendues ni cédées à des tiers.'),
        _h('Hébergement et transfert hors du Cameroun'),
        _p('Les données sont hébergées sur Google Firebase, dont les serveurs '
            'peuvent être situés hors du Cameroun. La loi subordonne un tel '
            'transfert à des garanties adéquates et à l\'autorisation préalable '
            'de l\'autorité de protection des données ; PagneShop s\'engage à '
            'accomplir cette formalité et à en informer les utilisateurs.'),
        _h('Durée de conservation'),
        _p('Compte : tant qu\'il est actif, puis suppression ou anonymisation. '
            'Commandes, paiements et preuves de livraison : durée des obligations '
            'légales de conservation des transactions électroniques et des '
            'pièces comptables, puis suppression. Codes de livraison : 48 h.'),
        _h('Vos droits'),
        _p('Accès, rectification, opposition, effacement (« droit à l\'oubli ») '
            'et retrait du consentement. Depuis « Mon compte », vous pouvez '
            'modifier vos informations et SUPPRIMER VOTRE COMPTE : vos données '
            'd\'identification sont alors effacées ou anonymisées, les '
            'enregistrements de transactions étant conservés sous forme '
            'anonymisée pour la durée légale. Pour toute demande : '
            '${kExploitant['dpo']}. Vous pouvez saisir l\'autorité de '
            'protection des données personnelles.'),
        _h('Sécurité'),
        _p('Accès aux données limité par des règles de sécurité serveur '
            '(chaque utilisateur n\'accède qu\'à ses propres données et à '
            'celles de ses commandes), chiffrement des échanges, codes de '
            'livraison signés cryptographiquement, journalisation des actions '
            'sensibles. Tout incident de sécurité affectant vos données vous '
            'sera notifié, ainsi qu\'aux autorités compétentes.'),
        _h('Messages promotionnels'),
        _p('Vous ne recevez d\'offres promotionnelles que si vous l\'avez '
            'accepté ; vous pouvez retirer ce choix à tout moment dans '
            '« Mon compte ».'),
        _ref('Art. 7 loi n° 2010/021 : prospection directe interdite sans '
            'consentement préalable.'),
      ]);
}
