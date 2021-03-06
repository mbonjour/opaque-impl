import pickle
import base64
import json
import hashlib

from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes, hmac
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

#
# Hardcoded values to simplify this current implementation.

sid  = 1                         # user id
id_u = 'bob'                     # username
id_s = 'very-secure-crypto.com'  # server "id"
ssid = 12345                     # session id


#
# Public elliptic curve (sec512r1).

p = 2 ** 521 - 1
a = 0x01FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFC
b = 0x0051953EB9618E1C9A1F929A21A0B68540EEA2DA725B99B315F3B8B489918EF109E156193951EC7E937B1652C0BD3BB1BF073573DF883D2C34F1EF451FD46B503F00
E = EllipticCurve(FiniteField(p), [a, b])

x = 0x00C6858E06B70404E9CD9E3ECB662395B4429C648139053FB521F828AF606B4D3DBAA14B5E77EFE75928FE1DC127A2FFA8DE3348B3C1856A429BF97E7E31C2E5BD66
y = 0x011839296A789A3BC0045C8A5FB42C7D1BD998F54449579B446817AFBD17273E662C97EE72995EF42640C550B9013FAD0761353C7086A272C24088BE94769FD16650
G = E(x, y)

n = 0x01FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFA51868783BF2F966B7FCC0148F709A5D03BB5C9B8899C47AEBB6FB71E91386409
Fn = FiniteField(n)

if not (n * G).is_zero():
    raise Error('Incorrect EC parameters')


#
# OPAQUE functions.

def gen_key():
    """
    Generate a random private and public key pair.
    """
    prv = Integer(Fn.random_element())
    return (prv, prv * G)

def h(*data):
    """
    The H function (SHA-512).
    """
    return hashlib.sha512(to_bytes(*data)).digest()

def hp(m):
    """
    The H' function. Insecure implementation.
    """
    return int.from_bytes(h(m), byteorder=sys.byteorder) * G

def pbkdf(pwd):
    """
    PBKDF function (Scrypt). According to the specs, these parameters can be
    public, so we hardcode them here.
    """

    # as mentionned in the RFC
    salt = b'\x00' * 16

    n = 2 ** 14  # 2 ** 20
    r = 8
    p = 1

    kdf = Scrypt(salt=salt, length=32, n=n, r=r, p=p, backend=default_backend())
    return kdf.derive(pwd)

def auth_enc(key, message):
    """
    Perform authenticated encryption on the message with the given key.
    """

    # Pad the message with 0x80 and 16 * 0x00 and then as many 0x00 needed for
    # length of the message to be a multiple of 128 bits (AES block size, as
    # we are using AES-GCM).
    # This ensures the last block is only 0, as described in 3.1.1 of the RFC.
    message += b'\x80' + b'\x00' * 16
    while len(message) % 16 != 0:
        message += b'\x00'

    # IV should be 0 according to RFC…
    iv = b'\x00' * 12

    return AESGCM(key).encrypt(iv, message, None)

def auth_dec(key, cipher):
    """
    Decrypt the cipher with the given key. The tag is automatically verified.
    """

    # IV is 0 according to RFC
    iv = b'\x00' * 12

    # decrypt and remove the last 0 block
    message = AESGCM(key).decrypt(iv, cipher, None)[:-16]

    # remove all 0 bytes until we reach the 0x80 byte
    while message[-1] == 0x00:
        message = message[:-1]

    # return the message after removing the 0x80 byte
    return message[:-1]

def on_curve(*points):
    """
    Check if the given points are all on the E curve.
    """
    res = True
    for p in points:
        x, y = p.xy()
        res = res and E.is_on_curve(x, y)
    return res

def key_ex_e(P, id, ssid):
    return b2i(h(P, id, ssid)) % n

def key_ex_s(p_s, x_s, P_u, X_u, X_s, id_s, id_u, ssid):
    """
    Server key-exchange formula.
    """
    e_u = key_ex_e(X_u, id_s, ssid)
    e_s = key_ex_e(X_s, id_u, ssid)
    return h((X_u + e_u * P_u) * (x_s + e_s * p_s))

def key_ex_u(p_u, x_u, P_s, X_s, X_u, id_s, id_u, ssid):
    """
    Client key-exchange formula.
    """
    e_u = key_ex_e(X_u, id_s, ssid)
    e_s = key_ex_e(X_s, id_u, ssid)
    return h((X_s + e_s * P_s) * (x_u + e_u * p_u))

def f(key, *message):
    """
    Pseudorandom function f (HMAC-SHA512).
    """
    h = hmac.HMAC(key, hashes.SHA512(), backend=default_backend())
    h.update(to_bytes(*message))
    return h.finalize()


#
# Send, receive helper functions.

def recv_json(sock):
    """
    Read data on the socket until the data can be properly deserialized as a
    JSON object.
    """

    data = b''
    while True:

        d = sock.recv(1024)
        if not d:
            continue
        try:
            data += d
            return json.loads(data)
        except:
            None

def send_json(sock, **data):
    """
    Send over the socket the keyword parameters as a JSON object.
    """

    dict = {}
    for name, value in data.items():

        vtype = type(value)
        if vtype is bytes:
            dict[name] = base64.b64encode(value).decode()

        elif vtype is sage.schemes.elliptic_curves.ell_point.EllipticCurvePoint_finite_field:
            dict.update(ecp2j(value, name))

        elif vtype is str or vtype is int or vtype is float:
            dict[name] = value

        else:
            raise ValueError("Cannot add value to JSON.")

    sock.sendall(json.dumps(dict).encode())


#
# Helper functions.

def i2b(i):
    """
    int to bytes
    """
    if i == 0:
        # special case, bit_length on 0 returns 0…
        return b'\x00'
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

def ecp2j(ecp, name):
    """
    elliptic curve point to JSON
    """
    x, y = ecp.xy()
    return { name + '_x': int(x), name + '_y': int(y) }

def j2ecp(j, name):
    """
    JSON to elliptic curve point
    """
    return E(j[name + '_x'], j[name + '_y'])

def j2b(j):
    """
    JSON to bytes
    """
    return base64.b64decode(j.encode())

def to_bytes(*objects):
    """
    Convert all args to bytes and return their concatenation.
    """

    data = b''
    for object in objects:

        vtype = type(object)
        if vtype is bytes:
            data += object

        elif vtype is sage.rings.integer.Integer or vtype is int:
            data += i2b(object)

        elif vtype is sage.schemes.elliptic_curves.ell_point.EllipticCurvePoint_finite_field:
            data += ecp2b(object)

        elif vtype is str:
            data += object.encode()

        else:
            raise ValueError("Cannot convert value to bytes.")

    return data
