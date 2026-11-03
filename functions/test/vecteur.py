# Vecteur de référence indépendant pour test/qr.test.js (même algo que Dart)
import hmac, hashlib
cle = bytes(range(1, 33))
print(hmac.new(cle, b'LIV123:depart:1700000000:1700172800', hashlib.sha256).hexdigest()[:32])
