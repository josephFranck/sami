'use strict';
// Textes des notifications envoyées par le serveur — FR et EN (mêmes textes
// que scripts/i18n/chaines.json ; le destinataire lit sa langue).
const T = {
  colisPrisCharge: { fr: 'Colis pris en charge 🛵', en: 'Parcel picked up 🛵' },
  livreurRecupere: { fr: 'Le livreur a récupéré votre commande — elle est en route !', en: 'The courier has collected your order — it is on its way!' },
  commandeLivree: { fr: 'Commande livrée 🎉', en: 'Order delivered 🎉' },
  colisArrive: { fr: 'Votre colis est arrivé. Donnez votre avis sur la boutique et le livreur !', en: 'Your parcel has arrived. Rate the shop and the courier!' },
  vetementLivre: { fr: 'Vêtement livré 🎉', en: 'Garment delivered 🎉' },
  confectionArrivee: { fr: 'Votre confection est arrivée. Votre reçu est disponible.', en: 'Your garment has arrived. Your receipt is available.' },
  tissuRecu: { fr: 'Tissu reçu ✂️', en: 'Fabric received ✂️' },
  pagneArriveAtelier: { fr: 'Le pagne est arrivé à votre atelier. La confection peut commencer.', en: 'The fabric has arrived at your workshop. Tailoring can start.' },
  parrainageReussi: { fr: 'Parrainage réussi 🎉', en: 'Referral successful 🎉' },
  bienvenueRecompensee: { fr: 'Bienvenue récompensée 🎁', en: 'Welcome reward 🎁' },
  avoirArrive: { fr: (m) => `${m} F d'avoir arrivent sur votre compte (validation en cours).`, en: (m) => `${m} F of credit are on their way to your account (validation in progress).` },
  nouvelleCourse: { fr: 'Nouvelle course 🛵', en: 'New delivery 🛵' },
  courseAssignee: { fr: (o, d) => `Récupérez le colis à ${o} et livrez à ${d}.`, en: (o, d) => `Pick up the parcel at ${o} and deliver to ${d}.` },
  livreurTrouve: { fr: 'Livreur trouvé 🛵', en: 'Courier found 🛵' },
  livreurEnRoute: { fr: 'Un livreur est assigné à votre commande.', en: 'A courier has been assigned to your order.' },
};

/** {titre, message, titreEn, messageEn} prêts pour la collection notifications */
function textes(cleTitre, cleMessage, ...args) {
  const r = (v, l) => (typeof v[l] === 'function' ? v[l](...args) : v[l]);
  return {
    titre: r(T[cleTitre], 'fr'),
    message: r(T[cleMessage], 'fr'),
    titreEn: r(T[cleTitre], 'en'),
    messageEn: r(T[cleMessage], 'en'),
  };
}

module.exports = { T, textes };
