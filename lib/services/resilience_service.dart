import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SERVICE DE RÉSILIENCE — Garoua-proof
//
// Problèmes couverts :
//   1. Coupure réseau pendant une action critique
//   2. Décharge batterie pendant saisie de formulaire
//   3. Double soumission après reconnexion
//   4. Actions en attente au redémarrage de l'app
//
// Architecture :
//   ConnectiviteService → surveille l'état réseau
//   FileAttenteOffline  → stocke les actions en attente localement
//   AutoSave            → sauvegarde formulaires en temps réel
//   IdempotenceService  → évite les doublons
// ═══════════════════════════════════════════════════════════════════════════

// ─── 1. Service de connectivité ───────────────────────────────────────────────

class ConnectiviteService {
  static final ConnectiviteService _instance = ConnectiviteService._();
  factory ConnectiviteService() => _instance;
  ConnectiviteService._();

  final _connectivity = Connectivity();
  final _controller = StreamController<bool>.broadcast();

  bool _estConnecte = true;
  bool get estConnecte => _estConnecte;
  Stream<bool> get stream => _controller.stream;

  static ConnectiviteService get instance => _instance;

  Future<void> init() async {
    // Vérifier l'état initial
    final result = await _connectivity.checkConnectivity();
    _estConnecte = _estConnecteDepuisResult(result);

    // Écouter les changements
    _connectivity.onConnectivityChanged.listen((result) {
      final etaitConnecte = _estConnecte;
      _estConnecte = _estConnecteDepuisResult(result);
      _controller.add(_estConnecte);

      if (!etaitConnecte && _estConnecte) {
        // Retour réseau → vider la file d'attente
        if (kDebugMode) print('[Connectivité] Réseau restauré — vidage de la file d\'attente');
        FileAttenteOffline.instance.viderFile();
      }
    });
  }

  // Tolérant aux deux API connectivity_plus :
  //  - v6.x : checkConnectivity() → List<ConnectivityResult>
  //  - v3/v4 : ConnectivityResult unique
  bool _estConnecteDepuisResult(dynamic result) {
    if (result is List) {
      return result.any((r) => r != ConnectivityResult.none);
    }
    return result != ConnectivityResult.none;
  }

  void dispose() {
    _controller.close();
  }
}

// ─── 2. File d'attente pour actions offline ───────────────────────────────────

enum TypeActionOffline {
  scanQR,
  passerCommande,
  confirmerLivraison,
  envoyerMessage,
  confirmerReception,
  mettreAJourStatut,
  uploadPhoto,
}

class ActionOffline {
  final String id;               // UUID unique pour idempotence
  final TypeActionOffline type;
  final Map<String, dynamic> payload;
  final DateTime dateCreation;
  int tentatives;
  String? erreurDerniereTentative;

  ActionOffline({
    required this.id,
    required this.type,
    required this.payload,
    required this.dateCreation,
    this.tentatives = 0,
    this.erreurDerniereTentative,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'payload': payload,
    'dateCreation': dateCreation.toIso8601String(),
    'tentatives': tentatives,
    'erreurDerniereTentative': erreurDerniereTentative,
  };

  factory ActionOffline.fromJson(Map<String, dynamic> j) => ActionOffline(
    id: j['id'] as String? ?? '',
    type: TypeActionOffline.values.firstWhere((e) => e.name == (j['type'] as String? ?? ''), orElse: () => TypeActionOffline.values.first),
    payload: Map<String, dynamic>.from(j['payload'] as Map),
    dateCreation: DateTime.parse(j['dateCreation'] as String? ?? ''),
    tentatives: j['tentatives'] as int? ?? 0,
    erreurDerniereTentative: j['erreurDerniereTentative'] as String?,
  );
}

class FileAttenteOffline {
  static final FileAttenteOffline _instance = FileAttenteOffline._();
  factory FileAttenteOffline() => _instance;
  FileAttenteOffline._();
  static FileAttenteOffline get instance => _instance;

  static const _kCle = 'file_attente_offline';
  static const _kMaxTentatives = 5;

  final _uuid = const Uuid();
  List<ActionOffline> _file = [];
  bool _enTraitement = false;

  Future<void> init() async {
    await _charger();
    // Démarrer le traitement si réseau disponible
    if (ConnectiviteService.instance.estConnecte && _file.isNotEmpty) {
      await viderFile();
    }
  }

  /// Ajouter une action à la file
  Future<String> ajouter({
    required TypeActionOffline type,
    required Map<String, dynamic> payload,
    String? idForce,  // pour idempotence (utiliser un ID existant)
  }) async {
    final id = idForce ?? _uuid.v4();
    // Éviter les doublons par ID
    if (_file.any((a) => a.id == id)) return id;

    final action = ActionOffline(
      id: id,
      type: type,
      payload: payload,
      dateCreation: DateTime.now(),
    );
    _file.add(action);
    await _sauvegarder();
    if (kDebugMode) print('[FileOffline] Action ajoutée : $type ($id)');

    // Si connecté, exécuter immédiatement
    if (ConnectiviteService.instance.estConnecte) {
      await viderFile();
    }
    return id;
  }

  /// Vider la file (exécuter toutes les actions en attente)
  Future<void> viderFile() async {
    if (_enTraitement || _file.isEmpty) return;
    _enTraitement = true;

    try {
      final aTraiter = List<ActionOffline>.from(_file);
      for (final action in aTraiter) {
        if (action.tentatives >= _kMaxTentatives) {
          // Trop de tentatives → notifier et supprimer
          _file.remove(action);
          _onEchecDefinitif(action);
          continue;
        }
        try {
          await _executer(action);
          _file.remove(action);
          if (kDebugMode) print('[FileOffline] ✅ Action exécutée : ${action.type}');
        } catch (e) {
          action.tentatives++;
          action.erreurDerniereTentative = e.toString();
          if (kDebugMode) print('[FileOffline] ❌ Tentative ${action.tentatives} échouée : $e');
        }
      }
    } finally {
      _enTraitement = false;
      await _sauvegarder();
    }
  }

  /// Exécuter une action selon son type
  Future<void> _executer(ActionOffline action) async {
    final p = action.payload;
    switch (action.type) {

      case TypeActionOffline.scanQR:
        await FirebaseFirestore.instance
            .collection('sous_commandes')
            .doc(p['sousCommandeId'] as String? ?? '')
            .collection('livraisons')
            .doc(p['livraisonId'] as String? ?? '')
            .update({
          'statut': p['statut'] as String? ?? '',
          'datePrisEnCharge': FieldValue.serverTimestamp(),
          'livreurId': p['livreurId'],
        });
        await FirebaseFirestore.instance
            .collection('sous_commandes')
            .doc(p['sousCommandeId'] as String? ?? '')
            .update({'statut': p['statutSousCommande'] as String});

      case TypeActionOffline.confirmerLivraison:
        await FirebaseFirestore.instance
            .collection('sous_commandes')
            .doc(p['sousCommandeId'] as String? ?? '')
            .collection('livraisons')
            .doc(p['livraisonId'] as String? ?? '')
            .update({
          'statut': 'livree',
          'dateLivraison': FieldValue.serverTimestamp(),
        });

      case TypeActionOffline.envoyerMessage:
        await FirebaseFirestore.instance
            .collection('conversations')
            .doc(p['convId'] as String? ?? '')
            .collection('messages')
            .doc(action.id) // ID idempotent
            .set({
          'id': action.id,
          'senderId': p['senderId'] as String? ?? '',
          'texte': p['texte'] as String? ?? '',
          'type': 'texte',
          'timestamp': FieldValue.serverTimestamp(),
          'lu': false,
        });

      case TypeActionOffline.mettreAJourStatut:
        await FirebaseFirestore.instance
            .collection(p['collection'] as String? ?? '')
            .doc(p['docId'] as String? ?? '')
            .update({p['champ'] as String: p['valeur']});

      case TypeActionOffline.confirmerReception:
        // Idempotent grâce à transaction Firestore
        await FirebaseFirestore.instance.runTransaction((txn) async {
          final ref = FirebaseFirestore.instance
              .collection('sous_commandes')
              .doc(p['sousCommandeId'] as String? ?? '');
          final doc = await txn.get(ref);
          if (!doc.exists) return;
          final statut = doc.data()?['statut'] as String?;
          // N'exécuter que si pas encore terminée
          if (statut != 'terminee') {
            txn.update(ref, {
              'statut': 'terminee',
              'dateTerminaison': FieldValue.serverTimestamp(),
            });
          }
        });

      default:
        throw UnimplementedError('Action ${action.type} non implémentée dans la file');
    }
  }

  void _onEchecDefinitif(ActionOffline action) {
    // TODO : notifier l'utilisateur / créer un ticket de support
    if (kDebugMode) {
      print('[FileOffline] ⛔ Échec définitif : ${action.type} après ${action.tentatives} tentatives');
    }
  }

  Future<void> _charger() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kCle);
    if (json == null) return;
    try {
      final liste = (jsonDecode(json) as List)
          .map((e) => ActionOffline.fromJson(e as Map<String, dynamic>))
          .toList();
      _file = liste;
      if (kDebugMode) print('[FileOffline] ${_file.length} actions chargées depuis le stockage local');
    } catch (e) {
      if (kDebugMode) print('[FileOffline] Erreur chargement : $e');
    }
  }

  Future<void> _sauvegarder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCle, jsonEncode(_file.map((a) => a.toJson()).toList()));
  }

  int get nombreEnAttente => _file.length;
  bool get aDesActionsEnAttente => _file.isNotEmpty;
}

// ─── 3. Autosave pour formulaires longs ───────────────────────────────────────

class AutoSave {
  static const _kPrefix = 'autosave_';
  static Timer? _timer;

  /// Sauvegarder un formulaire automatiquement (debounce 1.5s)
  static void sauvegarder(String cle, Map<String, dynamic> donnees) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1500), () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_kPrefix$cle', jsonEncode({
        'donnees': donnees,
        'dateSauvegarde': DateTime.now().toIso8601String(),
      }));
      if (kDebugMode) print('[AutoSave] 💾 Sauvegardé : $cle');
    });
  }

  /// Récupérer un formulaire sauvegardé
  static Future<Map<String, dynamic>?> charger(String cle) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('$_kPrefix$cle');
    if (json == null) return null;
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final date = DateTime.parse(data['dateSauvegarde'] as String? ?? '');
      // Ignorer si plus vieux que 7 jours
      if (DateTime.now().difference(date).inDays > 7) {
        await effacer(cle);
        return null;
      }
      return data['donnees'] as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Effacer la sauvegarde après soumission réussie
  static Future<void> effacer(String cle) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_kPrefix$cle');
  }

  /// Vérifier si une sauvegarde existe
  static Future<bool> exists(String cle) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('$_kPrefix$cle');
  }
}

// ─── 4. Widget indicateur de connectivité ────────────────────────────────────

import 'package:flutter/material.dart';

class BanniereOffline extends StatelessWidget {
  const BanniereOffline({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: ConnectiviteService.instance.stream,
      builder: (context, snap) {
        final estConnecte = snap.data ?? ConnectiviteService.instance.estConnecte;
        final nbEnAttente = FileAttenteOffline.instance.nombreEnAttente;

        if (estConnecte && nbEnAttente == 0) return const SizedBox.shrink();

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          color: estConnecte ? Colors.orange.shade600 : Colors.red.shade700,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
          child: Row(
            children: [
              Icon(
                estConnecte ? Icons.sync : Icons.signal_wifi_off,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  estConnecte
                      ? 'Synchronisation en cours ($nbEnAttente action${nbEnAttente > 1 ? "s" : ""} en attente)...'
                      : 'Pas de connexion — vos actions seront envoyées au retour du réseau',
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

// ─── 5. Mixin pour actions résilientes ────────────────────────────────────────
// À utiliser dans les pages/services qui font des actions critiques

mixin ActionResiliante {
  /// Exécuter une action avec fallback offline
  Future<T?> executerAvecResilience<T>({
    required Future<T> Function() action,
    required TypeActionOffline typeOffline,
    required Map<String, dynamic> payloadOffline,
    String? idIdempotent,
    T? valeurOptimiste,     // valeur à retourner immédiatement (UI optimiste)
    VoidCallback? onOffline,
  }) async {
    if (!ConnectiviteService.instance.estConnecte) {
      // Pas de réseau → mettre en file et retourner valeur optimiste
      await FileAttenteOffline.instance.ajouter(
        type: typeOffline,
        payload: payloadOffline,
        idForce: idIdempotent,
      );
      onOffline?.call();
      return valeurOptimiste;
    }

    try {
      return await action().timeout(const Duration(seconds: 15));
    } on TimeoutException {
      // Timeout → mettre en file
      await FileAttenteOffline.instance.ajouter(
        type: typeOffline,
        payload: payloadOffline,
        idForce: idIdempotent,
      );
      onOffline?.call();
      return valeurOptimiste;
    } catch (e) {
      // Autre erreur réseau
      if (_estErreurReseau(e)) {
        await FileAttenteOffline.instance.ajouter(
          type: typeOffline,
          payload: payloadOffline,
          idForce: idIdempotent,
        );
        onOffline?.call();
        return valeurOptimiste;
      }
      rethrow;
    }
  }

  bool _estErreurReseau(dynamic e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('network') ||
        msg.contains('socket') ||
        msg.contains('connection') ||
        msg.contains('timeout') ||
        msg.contains('unavailable');
  }
}

// ─── 6. Initialisation dans main.dart ─────────────────────────────────────────
// À appeler dans main() avant runApp()

Future<void> initResilienceServices() async {
  // Activer la persistence Firestore (cache offline natif)
  final settings = const Settings(persistenceEnabled: true, cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED);
  FirebaseFirestore.instance.settings = settings;

  // Démarrer les services de résilience
  await ConnectiviteService.instance.init();
  await FileAttenteOffline.instance.init();

  if (kDebugMode) print('[Résilience] Services initialisés');
}
