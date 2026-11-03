import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LANGUE DE L'APPLICATION — français et anglais (décision du 03/11/2026).
///
/// Une seule source pour toute l'app : `LangueService.instance.langue`
/// ('fr' | 'en'), persistée dans les préférences (clé `auth_lang`, déjà
/// utilisée par les écrans de connexion) et recopiée sur le profil
/// Firestore (`utilisateurs/{uid}.langue`) pour les usages serveur futurs.
///
/// Les textes sont servis par `Tr.s` (lib/l10n/tr.dart, généré) ; le
/// `MaterialApp` écoute ce service et se reconstruit au changement.
class LangueService extends ChangeNotifier {
  LangueService._();
  static final LangueService instance = LangueService._();

  static const String cle = 'auth_lang';
  static const List<String> disponibles = ['fr', 'en'];

  String _langue = 'fr';
  String get langue => _langue;
  Locale get locale => Locale(_langue);
  bool get estAnglais => _langue == 'en';

  /// À appeler au démarrage (après Firebase). Préférence enregistrée,
  /// sinon la langue du téléphone si c'est l'anglais, sinon le français.
  Future<void> charger() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sauvee = prefs.getString(cle);
      if (sauvee != null && disponibles.contains(sauvee)) {
        _langue = sauvee;
      } else {
        final tel = PlatformDispatcher.instance.locale.languageCode;
        _langue = tel == 'en' ? 'en' : 'fr';
      }
    } catch (_) {
      _langue = 'fr';
    }
    notifyListeners();
  }

  Future<void> changer(String nouvelle) async {
    if (!disponibles.contains(nouvelle) || nouvelle == _langue) return;
    _langue = nouvelle;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cle, nouvelle);
    } catch (_) {}
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance
            .collection('utilisateurs')
            .doc(uid)
            .set({'langue': nouvelle}, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  /// Libellé natif d'une langue (jamais traduit).
  static String libelle(String code) => switch (code) {
        'en' => 'English',
        _ => 'Français',
      };
  static String drapeau(String code) => code == 'en' ? '🇬🇧' : '🇫🇷';
}
