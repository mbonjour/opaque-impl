import os
import pickle
import hashlib

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes, hmac

#
# Public elliptic curve (sec512r1)

p = 2 ** 521 - 1
a = 0x01FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFC
b = 0x0051953EB9618E1C9A1F929A21A0B68540EEA2DA725B99B315F3B8B489918EF109E156193951EC7E937B1652C0BD3BB1BF073573DF883D2C34F1EF451FD46B503F00
E = EllipticCurve(FiniteField(p), [a, b])

x = 0x00C6858E06B70404E9CD9E3ECB662395B4429C648139053FB521F828AF606B4D3DBAA14B5E77EFE75928FE1DC127A2FFA8DE3348B3C1856A429BF97E7E31C2E5BD66
y = 0x011839296A789A3BC0045C8A5FB42C7D1BD998F54449579B446817AFBD17273E662C97EE72995EF42640C550B9013FAD0761353C7086A272C24088BE94769FD16650
G = E(x, y)

n = 0x01FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFA51868783BF2F966B7FCC0148F709A5D03BB5C9B8899C47AEBB6FB71E91386409
#(n * G).is_zero()  # must be true

Fn = FiniteField(n)

#
# Common functions

def i2b(i):
    """
    int to bytes
    """
    return int(i).to_bytes((int(i).bit_length() + 7) // 8, byteorder=sys.byteorder)

def b2i(b):
    """
    bytes to int
    """
    return int.from_bytes(b, byteorder=sys.byteorder)

def ecp2b(p):
    """
    elliptic curve point to bytes
    """
    x, y = p.xy()
    return i2b(int(x)) + i2b(int(y))

def h(m):
    """
    The H function (SHA-256)
    """
    return hashlib.sha256(m).digest()

def hp(m):
    """
    The H' function
    """
    return int.from_bytes(h(m), byteorder=sys.byteorder) * G

def auth_enc(key, message):
    
    # pad message with 0 as described in 3.1.1.
    message += b'\x00' * 16
    #while len(message) % 16 != 0:
    #    message += b'\x00'
    
    # iv should be 0 according to RFC
    iv = b'\x00' * 12  # os.urandom(12)
    
    # return iv and cipher
    return AESGCM(key).encrypt(iv, message, None)

def auth_dec(key, cipher):
    
    # iv should be 0 according to RFC
    iv = b'\x00' * 12  # os.urandom(12)
    
    # return message after removing the last 16 "0" bytes
    return AESGCM(key).decrypt(iv, cipher, None)[:-16]

def key_ex_s(p_s, x_s, P_u, X_u, X_s, id_s, id_u, ssid):
    
    e_u = b2i(h(ecp2b(X_u) + id_s + ssid)) % n
    e_s = b2i(h(ecp2b(X_s) + id_u + ssid)) % n
     
    return h(ecp2b((X_u + e_u * P_u) * (x_s + e_s * p_s)))

def key_ex_u(p_u, x_u, P_s, X_s, X_u, id_s, id_u, ssid):
    
    e_u = b2i(h(ecp2b(X_u) + id_s + ssid)) % n
    e_s = b2i(h(ecp2b(X_s) + id_u + ssid)) % n
    
    return h(ecp2b((X_s + e_s * P_s) * (x_u + e_u * p_u)))

def f(key, message):
    h = hmac.HMAC(key, hashes.SHA256(), backend=default_backend())
    h.update(message)
    return h.finalize()

def abort():
    sys.exit(-1)
    None