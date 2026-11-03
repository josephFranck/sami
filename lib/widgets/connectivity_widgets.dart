import 'package:flutter/material.dart';
import 'package:sami/services/resilience_service.dart';
import 'package:sami/services/stock_service.dart';
import 'package:sami/l10n/tr.dart';

const _kPrimary = Color(0xFF6A1B9A);

// ═══════════════════════════════════════════════════════════════════════════
// WIDGETS DE CONTRÔLE CONNECTIVITÉ + STOCK
//
// Principe :
//   Hors ligne → boutons d'action désactivés + message explicatif
//   En ligne   → boutons actifs + stock vérifié en temps réel
//
// Pourquoi désactiver plutôt que laisser en queue offline ?
//   → "Commander" sans réseau = fausse promesse
//   → Le stock affiché peut être périmé (un autre a pris le stock)
//   → Meilleure UX : expliquer clairement plutôt que créer des attentes
//
// Exception acceptée : scan QR livraison → action locale cryptographique
// ═══════════════════════════════════════════════════════════════════════════

// ─── 1. Bouton "Ajouter au panier" avec contrôle stock + connectivité ─────────

class BoutonAjouterPanier extends StatelessWidget {
  final String pagneId;
  final String pagneNom;
  final int quantiteDemandee;
  final VoidCallback onAjoute;

  const BoutonAjouterPanier({
    super.key,
    required this.pagneId,
    required this.pagneNom,
    required this.quantiteDemandee,
    required this.onAjoute,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      // 1. Écouter la connectivité
      stream: ConnectiviteService.instance.stream,
      initialData: ConnectiviteService.instance.estConnecte,
      builder: (context, snapConnex) {
        final estConnecte = snapConnex.data ?? true;

        if (!estConnecte) {
          // ─── HORS LIGNE : bouton désactivé avec explication ───────────────
          return _BoutonDesactive(
            label: Tr.s.ajouterPanier,
            icone: Icons.add_shopping_cart_outlined,
            raisonDesactivation: 'Connexion requise pour ajouter au panier',
          );
        }

        // ─── EN LIGNE : vérifier le stock en temps réel ────────────────────
        return StreamBuilder<int>(
          stream: StockService.streamStockDisponible(pagneId),
          builder: (context, snapStock) {
            final stock = snapStock.data ?? -1; // -1 = chargement
            final enChargement = !snapStock.hasData;

            if (enChargement) {
              return _BoutonChargement(label: Tr.s.verificationStock);
            }

            if (stock == 0) {
              return _BoutonDesactive(
                label: Tr.s.epuise,
                icone: Icons.block_outlined,
                raisonDesactivation: 'Ce pagne est actuellement épuisé',
                couleur: Colors.red,
              );
            }

            if (stock < quantiteDemandee) {
              return _BoutonDesactive(
                label: Tr.s.stockInsuffisantDisponible(stock),
                icone: Icons.warning_amber_outlined,
                raisonDesactivation: 'Seulement $stock disponible — réduisez la quantité',
                couleur: Colors.orange,
              );
            }

            // ✅ Stock OK + Connecté → bouton actif
            return _BoutonActif(
              label: Tr.s.ajouterPanier,
              icone: Icons.add_shopping_cart_outlined,
              stock: stock,
              onTap: onAjoute,
            );
          },
        );
      },
    );
  }
}

// ─── 2. Bouton "Commander" avec contrôle connectivité ────────────────────────

class BoutonCommander extends StatelessWidget {
  final double montant;
  final VoidCallback onCommander;
  final String labelMontant;

  const BoutonCommander({
    super.key,
    required this.montant,
    required this.onCommander,
    required this.labelMontant,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: ConnectiviteService.instance.stream,
      initialData: ConnectiviteService.instance.estConnecte,
      builder: (context, snap) {
        final estConnecte = snap.data ?? true;

        if (!estConnecte) {
          return Column(
            children: [
              _BanniereOfflineCommande(),
              const SizedBox(height: 8),
              _BoutonDesactive(
                label: Tr.s.impossibleCommanderHorsLigne,
                icone: Icons.wifi_off,
                raisonDesactivation: null, // message déjà dans la bannière
                pleineLargeur: true,
              ),
            ],
          );
        }

        return SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: onCommander,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.shopping_bag_outlined, size: 20),
                const SizedBox(width: 8),
                Text(
                  Tr.s.commander(labelMontant),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── 3. Bouton "Valider le paiement" ─────────────────────────────────────────

class BoutonValiderPaiement extends StatefulWidget {
  final double montant;
  final List<({String pagneId, int quantite})> articles;
  final Future<void> Function() onPayer;

  const BoutonValiderPaiement({
    super.key,
    required this.montant,
    required this.articles,
    required this.onPayer,
  });

  @override
  State<BoutonValiderPaiement> createState() => _BoutonValiderPaiementState();
}

class _BoutonValiderPaiementState extends State<BoutonValiderPaiement> {
  bool _enCours = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: ConnectiviteService.instance.stream,
      initialData: ConnectiviteService.instance.estConnecte,
      builder: (context, snap) {
        final estConnecte = snap.data ?? true;

        if (!estConnecte) {
          return _BoutonDesactive(
            label: Tr.s.paiementIndisponibleHorsLigne,
            icone: Icons.wifi_off,
            raisonDesactivation: 'Le paiement Mobile Money nécessite une connexion',
            pleineLargeur: true,
          );
        }

        return SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _enCours ? null : _payer,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _enCours
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      SizedBox(width: 10),
                      Text(Tr.s.verificationStock, style: TextStyle(fontSize: 14)),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline, size: 18),
                      SizedBox(width: 8),
                      Text(Tr.s.payerMaintenant, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Future<void> _payer() async {
    setState(() => _enCours = true);

    // Vérification finale du stock avant paiement (transaction atomique)
    final resultat = await StockService.confirmerStock(articles: widget.articles);

    if (!mounted) return;

    if (!resultat.succes) {
      setState(() => _enCours = false);
      // Afficher les articles dont le stock a changé
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
            SizedBox(width: 8),
            Text(Tr.s.stockModifie, style: TextStyle(fontSize: 16)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Tr.s.stockChangeDepuisVotreDerniere,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 10),
              ...resultat.erreurs.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  const Icon(Icons.circle, color: Colors.orange, size: 6),
                  const SizedBox(width: 8),
                  Expanded(child: Text(e, style: const TextStyle(fontSize: 13))),
                ]),
              )),
              const SizedBox(height: 10),
              Text(
                Tr.s.veuillezMettreJourVotrePanier,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white),
              child: Text(Tr.s.mettreJourPanier),
            ),
          ],
        ),
      );
      return;
    }

    // Stock OK → procéder au paiement
    try {
      await widget.onPayer();
    } catch (e) {
      if (mounted) {
        setState(() => _enCours = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Tr.s.erreurPaiement(e)), backgroundColor: Colors.red),
        );
      }
    }
  }
}

// ─── 4. Bannière hors ligne dans les pages critiques ─────────────────────────

class BanniereConnectivite extends StatelessWidget {
  /// Si true → affiche seulement quand offline
  /// Si false → affiche toujours (avec état connecté/déconnecté)
  final bool seulementOffline;

  const BanniereConnectivite({super.key, this.seulementOffline = true});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: ConnectiviteService.instance.stream,
      initialData: ConnectiviteService.instance.estConnecte,
      builder: (context, snap) {
        final estConnecte = snap.data ?? true;
        final nbAttente = FileAttenteOffline.instance.nombreEnAttente;

        if (seulementOffline && estConnecte && nbAttente == 0) {
          return const SizedBox.shrink();
        }

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          color: estConnecte
              ? (nbAttente > 0 ? Colors.orange.shade600 : Colors.green.shade600)
              : Colors.red.shade700,
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 14),
          child: Row(
            children: [
              Icon(
                estConnecte
                    ? (nbAttente > 0 ? Icons.sync : Icons.wifi)
                    : Icons.wifi_off,
                color: Colors.white,
                size: 15,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  estConnecte
                      ? (nbAttente > 0
                          ? Tr.s.synchronisationCoursAttente(nbAttente)
                          : Tr.s.connecte)
                      : Tr.s.horsLigneCertainesActionsSont,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── 5. Guard pour pages entières — redirige si offline ──────────────────────

class PageOnlyGuard extends StatelessWidget {
  final Widget child;
  final String messageOffline;
  final Widget? actionOffline;

  const PageOnlyGuard({
    super.key,
    required this.child,
    this.messageOffline = 'Cette fonctionnalité nécessite une connexion internet.',
    this.actionOffline,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: ConnectiviteService.instance.stream,
      initialData: ConnectiviteService.instance.estConnecte,
      builder: (context, snap) {
        final estConnecte = snap.data ?? true;
        if (estConnecte) return child;

        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_off, size: 72, color: Colors.grey.shade300),
                  const SizedBox(height: 20),
                  Text(
                    Tr.s.horsLigne,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    messageOffline,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  if (actionOffline != null) actionOffline!,
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    label: Text(Tr.s.retour2),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── 6. Indicateur de stock en temps réel ────────────────────────────────────

class IndicateurStock extends StatelessWidget {
  final String pagneId;
  final bool afficherNombre;

  const IndicateurStock({
    super.key,
    required this.pagneId,
    this.afficherNombre = true,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: StockService.streamStockDisponible(pagneId),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final stock = snap.data!;

        if (stock == 0) {
          return _Badge(Tr.s.epuise, Colors.red);
        }
        if (stock <= 3) {
          return _Badge(
            afficherNombre ? Tr.s.plusQue(stock) : Tr.s.stockLimite,
            Colors.orange,
          );
        }
        return const SizedBox.shrink(); // Stock normal → pas de badge
      },
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color couleur;
  const _Badge(this.label, this.couleur);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: couleur.withOpacity(0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: couleur.withOpacity(0.4)),
    ),
    child: Text(label, style: TextStyle(color: couleur, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}

// ─── Widgets internes ─────────────────────────────────────────────────────────

class _BoutonActif extends StatelessWidget {
  final String label;
  final IconData icone;
  final int stock;
  final VoidCallback onTap;

  const _BoutonActif({required this.label, required this.icone,
    required this.stock, required this.onTap});

  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
    onPressed: onTap,
    icon: Icon(icone, size: 18),
    label: Text(label),
    style: ElevatedButton.styleFrom(
      backgroundColor: _kPrimary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

class _BoutonDesactive extends StatelessWidget {
  final String label;
  final IconData icone;
  final String? raisonDesactivation;
  final Color couleur;
  final bool pleineLargeur;

  const _BoutonDesactive({
    required this.label,
    required this.icone,
    required this.raisonDesactivation,
    this.couleur = Colors.grey,
    this.pleineLargeur = false,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: pleineLargeur ? double.infinity : null,
        height: 48,
        child: ElevatedButton.icon(
          onPressed: null, // désactivé
          icon: Icon(icone, size: 18),
          label: Text(label),
          style: ElevatedButton.styleFrom(
            disabledBackgroundColor: couleur.withOpacity(0.12),
            disabledForegroundColor: couleur,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      if (raisonDesactivation != null) ...[
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.info_outline, size: 12, color: couleur.withOpacity(0.7)),
          const SizedBox(width: 4),
          Text(raisonDesactivation!,
              style: TextStyle(fontSize: 11, color: couleur.withOpacity(0.8))),
        ]),
      ],
    ],
  );
}

class _BoutonChargement extends StatelessWidget {
  final String label;
  const _BoutonChargement({required this.label});

  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
    onPressed: null,
    icon: const SizedBox(width: 16, height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)),
    label: Text(label),
    style: ElevatedButton.styleFrom(
      disabledBackgroundColor: Colors.grey.shade300,
      disabledForegroundColor: Colors.grey,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

class _BanniereOfflineCommande extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.orange.shade200),
    ),
    child: Row(
      children: [
        Icon(Icons.wifi_off, color: Colors.orange, size: 18),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            Tr.s.vousEtesHorsLigneReconnectez,
            style: TextStyle(color: Colors.orange, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}
