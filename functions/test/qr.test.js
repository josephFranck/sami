'use strict';
const test = require('node:test');
const assert = require('node:assert');
const qr = require('../src/qr');

test('token : génération puis vérification', () => {
  const cle = qr.genererCle();
  assert.strictEqual(cle.length, 44); // 32 octets base64 AVEC padding (comme Dart base64Url)
  const t = qr.genererToken('LIV123', 'depart', cle, 1_700_000_000);
  const v = qr.verifierToken(t.encode, cle, 'LIV123', 'depart', 1_700_000_100);
  assert.ok(v.ok, JSON.stringify(v));
  assert.strictEqual(qr.verifierToken(t.encode, cle, 'LIV123', 'arrivee').raison, 'mauvaisType');
  assert.strictEqual(qr.verifierToken(t.encode, cle, 'AUTRE', 'depart').raison, 'mauvaiseLivraison');
  assert.strictEqual(qr.verifierToken(t.encode, cle, 'LIV123', 'depart', 1_700_000_000 + qr.VALIDITE_S + 1).raison, 'expire');
  assert.strictEqual(qr.verifierToken(t.encode, qr.genererCle(), 'LIV123', 'depart', 1_700_000_100).raison, 'signatureInvalide');
  assert.strictEqual(qr.verifierToken('pas-un-token', cle, 'LIV123', 'depart', 1_700_000_100).raison, 'formatInvalide');
});

test('code court : 6 chiffres, déterministe', () => {
  const cle = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='; // 32 octets nuls
  const c = qr.codeCourt('LIV123', cle);
  assert.match(c, /^\d{6}$/);
  assert.strictEqual(c, qr.codeCourt('LIV123', cle));
  assert.ok(qr.verifierCodeCourt('LIV123', cle, ` ${c} `));
  assert.ok(!qr.verifierCodeCourt('LIV123', cle, '000001'));
});

test('vecteur de référence (même algorithme que Dart, calculé en Python)', () => {
  // clé = 32 octets 0x01..0x20, payload 'LIV|depart' — voir test/vecteur.py
  const cle = Buffer.from(Array.from({ length: 32 }, (_, i) => i + 1)).toString('base64').replace(/\+/g, '-').replace(/\//g, '_');
  const sig = qr.hmacHex32(cle, 'LIV123:depart:1700000000:1700172800');
  // calculé indépendamment en Python (hmac/sha256) : test/vecteur.py
  assert.strictEqual(sig, 'f5834d0deb60185affd847e8b5399b5a');
});
