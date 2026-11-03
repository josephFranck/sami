import 'package:flutter/material.dart';

const _kPrimary = Color(0xFF6A1B9A);

/// CONDITIONS D'UTILISATION & CONFIDENTIALITÉ — exigées par la loi
/// camerounaise (n°2024/017 protection des données, loi 2010/021 sur le
/// commerce électronique) et par le Play Store.
class ConditionsPage extends StatelessWidget {
  const ConditionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Conditions & confidentialité'),
          backgroundColor: _kPrimary,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [Tab(text: 'Utilisation'), Tab(text: 'Confidentialité')],
          ),
        ),
        body: TabBarView(children: [_cgu(), _confidentialite()]),
      ),
    );
  }

  Widget _texte(List<(String, String)> sections) => ListView(
        padding: const EdgeInsets.all(16),
        children: sections
            .map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.$1,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: _kPrimary)),
                      const SizedBox(height: 4),
                      Text(s.$2,
                          style: const TextStyle(fontSize: 13, height: 1.45)),
                    ],
                  ),
                ))
            .toList(),
      );

  Widget _cgu() => _texte(const [
        ('1. Objet',
            'SAMI est une place de marché mettant en relation acheteurs, '
                'boutiques de pagnes, couturiers et livreurs à Garoua '
                '(Cameroun). SAMI n\'est ni vendeur des articles ni employeur '
                'des partenaires : elle fournit la mise en relation, le suivi, '
                'la sécurisation des remises et la médiation.'),
        ('2. Comptes',
            'L\'inscription requiert des informations exactes. Un compte est '
                'personnel. Les partenaires (boutiquiers, couturiers, '
                'livreurs) sont validés après examen de leur dossier ; SAMI '
                'peut suspendre un compte en cas de fraude, contrefaçon ou '
                'comportement abusif.'),
        ('3. Commandes et prix',
            'Les prix sont affichés en FCFA. Pour les modèles « sur devis », '
                'le prix indicatif est confirmé par le couturier et accepté '
                'par le client avant confection. La commande d\'un article '
                'avec couture réserve le tissu dès la validation.'),
        ('4. Paiement',
            'Selon les phases du service : paiement à la livraison (espèces) '
                'ou Mobile Money. Les fonds des ventes sont reversés aux '
                'partenaires après confirmation de la livraison, déduction '
                'faite des commissions et frais affichés.'),
        ('5. Livraison et remises',
            'Les remises sont sécurisées par QR code, code de réception, '
                'signature ou photo. Le client doit vérifier l\'article à la '
                'réception. Les livraisons signalées anormales sont vérifiées '
                'avant tout paiement.'),
        ('6. Annulation, retours, litiges',
            'Un devis refusé annule la commande et restitue le tissu au '
                'stock. Tout litige (article non conforme, retard anormal) '
                'doit être signalé sous 48 h via l\'application ; SAMI arbitre '
                'sur la base des preuves enregistrées (photos, scans, GPS).'),
        ('7. Obligations des partenaires',
            'Les boutiques garantissent l\'authenticité et la disponibilité '
                'des articles publiés. Les couturiers respectent les mesures '
                'et délais convenus et photographient le vêtement fini. Les '
                'livreurs remettent les encaissements selon les règles de la '
                'plateforme.'),
        ('8. Propriété et contenu',
            'Les photos et descriptions publiées restent la propriété de '
                'leurs auteurs, qui accordent à SAMI une licence d\'affichage '
                'et de promotion (y compris le partage de fiches produits).'),
        ('9. Responsabilité',
            'SAMI met en œuvre des moyens raisonnables de sécurité et de '
                'médiation mais ne saurait être tenue responsable des '
                'dommages indirects. Le service peut évoluer ; une version '
                'minimale de l\'application peut être exigée.'),
        ('10. Droit applicable',
            'Les présentes conditions sont régies par le droit camerounais '
                '(not. loi n°2010/021 sur le commerce électronique). Tout '
                'litige non résolu à l\'amiable relève des juridictions de '
                'Garoua.'),
      ]);

  Widget _confidentialite() => _texte(const [
        ('Données collectées',
            'Compte (nom, téléphone, e-mail), adresses et points GPS de '
                'livraison, mesures corporelles pour la couture, historique '
                'de commandes, messages échangés via le chat, et pour les '
                'candidatures partenaires : pièce d\'identité et position de '
                'l\'atelier ou de la boutique.'),
        ('Usage',
            'Ces données servent exclusivement au fonctionnement du service : '
                'exécution des commandes, confection sur mesure, guidage des '
                'livraisons, sécurisation des remises, prévention de la '
                'fraude et médiation des litiges. Aucune vente de données à '
                'des tiers.'),
        ('Pièces d\'identité',
            'La photo de la pièce fournie lors d\'une candidature sert '
                'uniquement à la vérification du dossier et est supprimée '
                'après traitement (validation ou refus).'),
        ('Conservation et sécurité',
            'Les données sont hébergées sur des infrastructures sécurisées '
                'et conservées le temps nécessaire au service et aux '
                'obligations légales. Les preuves de livraison (photos, '
                'scans) sont conservées pour la durée de garantie et de '
                'médiation.'),
        ('Vos droits (loi n°2024/017)',
            'Conformément à la loi camerounaise sur la protection des '
                'données personnelles, vous disposez d\'un droit d\'accès, de '
                'rectification et de suppression de vos données. Exercez-le '
                'depuis votre compte ou en contactant le support via le chat '
                'de l\'application.'),
        ('Contact',
            'Pour toute question relative à vos données : rubrique '
                '« Messages » de l\'application, ou l\'adresse indiquée sur la '
                'fiche Play Store de SAMI.'),
      ]);
}
