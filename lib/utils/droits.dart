import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sami/models/utilisateur.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SYSTÈME DE DROITS D'ACCÈS CENTRALISÉ
//
// Rôles disponibles :
//   'client'      → achète, commande, chatte
//   'boutiquier'  → gère sa boutique et ses pagnes
//   'couturier'   → gère ses modèles et commandes couture
//   'livreur'     → gère ses livraisons
//   'admin'       → accès total, gestion utilisateurs, stats
//
// Utilisation :
//   if (Droits.peutAjouterPagne(utilisateur)) { ... }
//   if (Droits.estAdmin(utilisateur)) { ... }
//   Droits.fabBoutiquier(context, utilisateur, onTap: () => ...)
// ═══════════════════════════════════════════════════════════════════════════

class Droits {

  // ── Vérifications de rôle de base ─────────────────────────────────────────

  static bool estAdmin(Utilisateur? u) => u?.role == 'admin';
  static bool estBoutiquier(Utilisateur? u) => (u?.aRole('boutiquier') ?? false) || estAdmin(u);
  static bool estCouturier(Utilisateur? u) => (u?.aRole('couturier') ?? false) || estAdmin(u);
  static bool estLivreur(Utilisateur? u) => (u?.aRole('livreur') ?? false) || estAdmin(u);

  /// PERMISSIONS GRANULAIRES : l'admin a tout ; un « agent » (mini-admin)
  /// n'a que les droits cochés. Permissions : 'candidatures', 'litiges',
  /// 'evenements', 'boutiques', 'reversements', 'utilisateurs', 'parametres'.
  static bool peut(Utilisateur? u, String permission) {
    if (estAdmin(u)) return true;
    if (u?.role == 'agent') return u!.permissions.contains(permission);
    return false;
  }

  /// A au moins un droit d'administration (affichage de la section du menu).
  static bool estStaff(Utilisateur? u) =>
      estAdmin(u) || (u?.role == 'agent' && (u?.permissions.isNotEmpty ?? false));
  // TOUT compte connecté est client (décision 03/11/2026)
  static bool estClient(Utilisateur? u) => u != null;
  static bool estConnecte(Utilisateur? u) => u != null;

  // ── Droits sur les PAGNES ──────────────────────────────────────────────────

  static bool peutVoirPagnes(Utilisateur? u) => true;
  static bool peutAjouterPagne(Utilisateur? u) => estBoutiquier(u);
  static bool peutModifierPagne(Utilisateur? u, String? boutiqueIdPagne) {
    if (estAdmin(u)) return true;
    // Le boutiquier ne peut modifier que ses propres pagnes
    return estBoutiquier(u);
  }
  static bool peutSupprimerPagne(Utilisateur? u, String? boutiqueIdPagne) {
    if (estAdmin(u)) return true;
    return estBoutiquier(u);
  }

  // ── Droits sur les BOUTIQUES ──────────────────────────────────────────────

  static bool peutVoirBoutiques(Utilisateur? u) => true;
  static bool peutAjouterBoutique(Utilisateur? u) => estAdmin(u);
  static bool peutModifierBoutique(Utilisateur? u, List<String> gerants) {
    if (estAdmin(u)) return true;
    return gerants.contains(u?.id ?? '');
  }
  static bool peutSupprimerBoutique(Utilisateur? u) => estAdmin(u);

  // ── Droits sur les CATÉGORIES ─────────────────────────────────────────────

  static bool peutVoirCategories(Utilisateur? u) => true;
  static bool peutGererCategories(Utilisateur? u) => estAdmin(u);

  // ── Droits sur les COUTURIERS ─────────────────────────────────────────────

  static bool peutVoirCouturiers(Utilisateur? u) => true;
  static bool peutAjouterModele(Utilisateur? u) => estCouturier(u);
  static bool peutModifierModele(Utilisateur? u, String couturierId) {
    if (estAdmin(u)) return true;
    return u?.id == couturierId;
  }

  // ── Droits sur les COMMANDES ──────────────────────────────────────────────

  static bool peutVoirCommandes(Utilisateur? u) => estConnecte(u);
  static bool peutAnnulerCommande(Utilisateur? u, String clientId) {
    if (estAdmin(u)) return true;
    return u?.id == clientId;
  }
  static bool peutGererCommandes(Utilisateur? u) => estBoutiquier(u) || estAdmin(u);

  // ── Droits sur les LIVRAISONS ─────────────────────────────────────────────

  static bool peutVoirLivraisons(Utilisateur? u) => estConnecte(u);
  static bool peutGererLivraisons(Utilisateur? u) => estLivreur(u) || estAdmin(u);
  static bool peutSuperviserLivraisons(Utilisateur? u) => estAdmin(u);

  // ── Droits sur les UTILISATEURS ───────────────────────────────────────────

  static bool peutVoirUtilisateurs(Utilisateur? u) => estAdmin(u);
  static bool peutModifierUtilisateur(Utilisateur? u, String userId) {
    if (estAdmin(u)) return true;
    return u?.id == userId; // peut modifier son propre profil
  }
  static bool peutSupprimerUtilisateur(Utilisateur? u) => estAdmin(u);
  static bool peutChangerRole(Utilisateur? u) => estAdmin(u);

  // ── Droits sur les RETOURS ────────────────────────────────────────────────

  static bool peutInitierRetour(Utilisateur? u, String clientId) {
    if (estAdmin(u)) return true;
    return u?.id == clientId || estBoutiquier(u);
  }
  static bool peutValiderRetour(Utilisateur? u) => estAdmin(u);

  // ── Droits sur les STATISTIQUES ───────────────────────────────────────────

  static bool peutVoirStatsGlobales(Utilisateur? u) => estAdmin(u);
  static bool peutVoirStatsBoutique(Utilisateur? u, List<String> gerants) {
    if (estAdmin(u)) return true;
    return gerants.contains(u?.id ?? '');
  }

  // ── Chargement de l'utilisateur courant ───────────────────────────────────

  static Future<Utilisateur?> utilisateurCourant() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return Utilisateur.fromUid(user.uid);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // WIDGETS DE CONTRÔLE D'ACCÈS
  // ══════════════════════════════════════════════════════════════════════════

  /// FAB conditionnel — n'apparaît que si l'utilisateur a le droit
  static Widget? fab({
    required bool condition,
    required VoidCallback onTap,
    IconData icone = Icons.add,
    String? tooltip,
    Color couleur = const Color(0xFF6A1B9A),
  }) {
    if (!condition) return null;
    return FloatingActionButton(
      onPressed: onTap,
      backgroundColor: couleur,
      foregroundColor: Colors.white,
      tooltip: tooltip,
      child: Icon(icone),
    );
  }

  /// Badge de rôle coloré
  static Widget badgeRole(String role) {
    final (couleur, label) = switch (role) {
      'admin'      => (Colors.red, 'Admin'),
      'boutiquier' => (const Color(0xFF6A1B9A), 'Boutiquier'),
      'couturier'  => (Colors.teal, 'Couturier'),
      'livreur'    => (Colors.orange, 'Livreur'),
      _            => (Colors.grey, 'Client'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: couleur.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: couleur.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: couleur,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Widget qui n'affiche son enfant que si la condition est vraie
  static Widget si({required bool condition, required Widget child}) {
    return condition ? child : const SizedBox.shrink();
  }

  /// Actions de liste conditionnelles (modifier, supprimer)
  static List<Widget> actionsListe({
    required bool peutModifier,
    required bool peutSupprimer,
    required VoidCallback onModifier,
    required VoidCallback onSupprimer,
    String labelModifier = 'Modifier',
    String labelSupprimer = 'Supprimer',
  }) {
    return [
      if (peutModifier)
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 20),
          color: const Color(0xFF6A1B9A),
          tooltip: labelModifier,
          onPressed: onModifier,
        ),
      if (peutSupprimer)
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          color: Colors.red,
          tooltip: labelSupprimer,
          onPressed: onSupprimer,
        ),
    ];
  }

  /// Dialog de confirmation de suppression
  static Future<bool> confirmerSuppression(
    BuildContext context, {
    required String nom,
    String message = 'Cette action est irréversible.',
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text('Supprimer "$nom" ?', style: const TextStyle(fontSize: 16))),
        ]),
        content: Text(message, style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Snackbar d'accès refusé
  static void accesRefuse(BuildContext context, [String? message]) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message ?? 'Accès refusé — droits insuffisants'),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }
}

// ─── Mixin pour les pages qui nécessitent un utilisateur connecté ────────────

mixin PageProtegee<T extends StatefulWidget> on State<T> {
  Utilisateur? utilisateur;
  bool chargementUtilisateur = true;

  Future<void> chargerUtilisateur() async {
    final u = await Droits.utilisateurCourant();
    if (mounted) setState(() { utilisateur = u; chargementUtilisateur = false; });
  }

  Widget buildAvecDroits({
    required Widget Function(Utilisateur u) builder,
    Widget? chargement,
    Widget? nonConnecte,
  }) {
    if (chargementUtilisateur) {
      return chargement ?? const Center(child: CircularProgressIndicator(color: Color(0xFF6A1B9A)));
    }
    if (utilisateur == null) {
      return nonConnecte ?? const Center(
        child: Text('Connectez-vous pour accéder à cette page',
            style: TextStyle(color: Colors.grey)),
      );
    }
    return builder(utilisateur!);
  }
}
