// Traductions pour les pages d'authentification
// FR · EN · FF (Fulfulde)

enum AuthLang { fr, en, ff }

class AuthI18n {
  final AuthLang lang;
  const AuthI18n(this.lang);

  // ── Général ───────────────────────────────────────────────────────────────
  String get appNom     => 'PagneShop';
  String get appSlogan  => switch (lang) {
    AuthLang.fr => 'Le marché de pagnes de Garoua',
    AuthLang.en => 'Garoua\'s fabric marketplace',
    AuthLang.ff => 'Suudu lacciri Garoua',
  };

  // ── Login ─────────────────────────────────────────────────────────────────
  String get connexion      => switch (lang) { AuthLang.fr => 'Connexion', AuthLang.en => 'Sign in', AuthLang.ff => 'Naadde' };
  String get bienvenue      => switch (lang) { AuthLang.fr => 'Bienvenue !', AuthLang.en => 'Welcome!', AuthLang.ff => 'Jaaraama !' };
  String get email          => switch (lang) { AuthLang.fr => 'Adresse e-mail', AuthLang.en => 'Email address', AuthLang.ff => 'Imaayel maa' };
  String get motDePasse     => switch (lang) { AuthLang.fr => 'Mot de passe', AuthLang.en => 'Password', AuthLang.ff => 'Guddigal sirri' };
  String get seConnecter    => switch (lang) { AuthLang.fr => 'Se connecter', AuthLang.en => 'Sign in', AuthLang.ff => 'Naado' };
  String get mdpOublie      => switch (lang) { AuthLang.fr => 'Mot de passe oublié ?', AuthLang.en => 'Forgot password?', AuthLang.ff => 'A yiɗaani guddigal maa ?' };
  String get pasDeCompte    => switch (lang) { AuthLang.fr => 'Pas encore de compte ?', AuthLang.en => 'No account yet?', AuthLang.ff => 'A alaa konte tee ?' };
  String get sInscrire      => switch (lang) { AuthLang.fr => 'S\'inscrire', AuthLang.en => 'Sign up', AuthLang.ff => 'Winndito' };

  // ── Signup ────────────────────────────────────────────────────────────────
  String get inscription    => switch (lang) { AuthLang.fr => 'Créer un compte', AuthLang.en => 'Create account', AuthLang.ff => 'Woppude konte keso' };
  String get nom            => switch (lang) { AuthLang.fr => 'Nom', AuthLang.en => 'Last name', AuthLang.ff => 'Innde maa' };
  String get prenom         => switch (lang) { AuthLang.fr => 'Prénom', AuthLang.en => 'First name', AuthLang.ff => 'Tummbaare maa' };
  String get telephone      => switch (lang) { AuthLang.fr => 'Téléphone', AuthLang.en => 'Phone number', AuthLang.ff => 'Nambur telefon' };
  String get confirmerMdp   => switch (lang) { AuthLang.fr => 'Confirmer le mot de passe', AuthLang.en => 'Confirm password', AuthLang.ff => 'Jaɓɓo guddigal' };
  String get quartier       => switch (lang) { AuthLang.fr => 'Quartier', AuthLang.en => 'Neighbourhood', AuthLang.ff => 'Saare' };
  String get ville          => switch (lang) { AuthLang.fr => 'Ville', AuthLang.en => 'City', AuthLang.ff => 'Wuro' };
  String get codeParrainage => switch (lang) { AuthLang.fr => 'Code de parrainage (optionnel)', AuthLang.en => 'Referral code (optional)', AuthLang.ff => 'Koodowel parrainage (woppu si alaa)' };
  String get creerCompte    => switch (lang) { AuthLang.fr => 'Créer mon compte', AuthLang.en => 'Create my account', AuthLang.ff => 'Woppude konte am' };
  String get dejaCompte     => switch (lang) { AuthLang.fr => 'Déjà un compte ?', AuthLang.en => 'Already have an account?', AuthLang.ff => 'A jogii konte tee ?' };

  // ── Reset password ────────────────────────────────────────────────────────
  String get resetTitre     => switch (lang) { AuthLang.fr => 'Mot de passe oublié', AuthLang.en => 'Forgot password', AuthLang.ff => 'Guddigal wonaa tawaaka' };
  String get resetDesc      => switch (lang) {
    AuthLang.fr => 'Entrez votre e-mail. Vous recevrez un lien pour réinitialiser votre mot de passe.',
    AuthLang.en => 'Enter your email. You\'ll receive a link to reset your password.',
    AuthLang.ff => 'Wowwu imaayel maa. A accanan liyaŋ mo faati e rewde guddigal maa.',
  };
  String get envoyer        => switch (lang) { AuthLang.fr => 'Envoyer le lien', AuthLang.en => 'Send reset link', AuthLang.ff => 'Neldu liyaŋ ngol' };
  String get resetEnvoye    => switch (lang) {
    AuthLang.fr => 'Lien envoyé ! Vérifiez votre boîte mail.',
    AuthLang.en => 'Link sent! Check your inbox.',
    AuthLang.ff => 'Liyaŋ neldaama ! Ƴeew saare imaayel maa.',
  };
  String get retourConnexion => switch (lang) { AuthLang.fr => 'Retour à la connexion', AuthLang.en => 'Back to sign in', AuthLang.ff => 'Rutto e naadde' };

  // ── Validation ────────────────────────────────────────────────────────────
  String get champRequis    => switch (lang) { AuthLang.fr => 'Champ requis', AuthLang.en => 'Required field', AuthLang.ff => 'Golle haɗɗiiɗe' };
  String get emailInvalide  => switch (lang) { AuthLang.fr => 'E-mail invalide', AuthLang.en => 'Invalid email', AuthLang.ff => 'Imaayel mo haɗɗaano' };
  String get mdpTropCourt   => switch (lang) { AuthLang.fr => 'Au moins 6 caractères', AuthLang.en => 'At least 6 characters', AuthLang.ff => '6 daɓɓe ko famɗi' };
  String get mdpDiff        => switch (lang) { AuthLang.fr => 'Les mots de passe ne correspondent pas', AuthLang.en => 'Passwords don\'t match', AuthLang.ff => 'Guddigal ɗiɗi ɓuri yaawde' };
  String get telInvalide    => switch (lang) { AuthLang.fr => 'Numéro invalide (ex: 6XXXXXXXX)', AuthLang.en => 'Invalid number (e.g. 6XXXXXXXX)', AuthLang.ff => 'Nambur bone (misal: 6XXXXXXXX)' };

  // ── Erreurs Firebase ──────────────────────────────────────────────────────
  String erreurFirebase(String code) => switch (code) {
    'user-not-found' => switch (lang) {
      AuthLang.fr => 'Aucun compte avec cet e-mail',
      AuthLang.en => 'No account with this email',
      AuthLang.ff => 'Konte alaa e imaayel ngool',
    },
    'wrong-password' => switch (lang) {
      AuthLang.fr => 'Mot de passe incorrect',
      AuthLang.en => 'Wrong password',
      AuthLang.ff => 'Guddigal jaɓaaka',
    },
    'email-already-in-use' => switch (lang) {
      AuthLang.fr => 'Cet e-mail est déjà utilisé',
      AuthLang.en => 'This email is already in use',
      AuthLang.ff => 'Imaayel ngool jeyaa',
    },
    'invalid-email' => switch (lang) {
      AuthLang.fr => 'Adresse e-mail invalide',
      AuthLang.en => 'Invalid email address',
      AuthLang.ff => 'Imaayel mo haɗɗaano',
    },
    'network-request-failed' => switch (lang) {
      AuthLang.fr => 'Pas de connexion internet',
      AuthLang.en => 'No internet connection',
      AuthLang.ff => 'Alaa ɗeɓɗeɓe',
    },
    'too-many-requests' => switch (lang) {
      AuthLang.fr => 'Trop de tentatives. Attendez quelques minutes.',
      AuthLang.en => 'Too many attempts. Wait a few minutes.',
      AuthLang.ff => 'Tentatiiji keewɗi. Attoo yeeso.',
    },
    _ => switch (lang) {
      AuthLang.fr => 'Une erreur est survenue. Réessayez.',
      AuthLang.en => 'An error occurred. Please try again.',
      AuthLang.ff => 'Juumre warii. Tekkito.',
    },
  };
}
