from opaque.common import *

def register(send, recv, data):
    """
    Register a client's password.

    :param send: a function used to send data to the client
    :param recv: a function used to receive data from the client
    :param data: the data received from the client
    :returns   : the user data to be stored in the database
    """

    # Choose a private and public key pair (p_s, P_s).
    p_s, P_s = gen_key()

    # Choose random key for the OPRF (different for each user).
    k_s = Integer(Fn.random_element())

    # Compute beta.
    alpha = j2ecp(data, 'alpha')
    beta = k_s * alpha

    # Send v_u and beta to the client.
    send(beta=beta, P_s=P_s)

    # Receive c and P_u from the client.
    data = recv()
    P_u = j2ecp(data, 'P_u')

    # Return the client data to be store in the database.
    return {
        'k_s': k_s,
        'p_s': p_s,
        'P_s': P_s,
        'P_u': P_u,
        'c' : data['c']
    }

def login(send, recv, client_data, data):
    """
    Log in a client.

    :param send: a function used to send data to the client
    :param recv: a function used to receive data from the client
    :param client_data: the client data stored during the registration phase
    :param data: the data received from the client
    :returns: a tuple (X, sid, ssid) where X is the symmetric key in case of
              success, or None in case of failure.
    """

    # Choose a private and public key pair (x_s, X_s)
    x_s, X_s = gen_key()

    k_s = client_data['k_s']
    p_s = client_data['p_s']
    P_s = client_data['P_s']
    P_u = client_data['P_u']
    c = client_data['c']

    # Compute beta.
    alpha = j2ecp(data, 'alpha')
    beta = k_s * alpha

    # Check alpha, X_u and P_u are on the curve. P_s should be on the curve as
    # it was computed by the server.
    X_u = j2ecp(data, 'X_u')
    if not on_curve(alpha, X_u, P_u):
        return (None, sid, ssid)

    # Compute ssid', K, SK and A_s.
    ssidp = h(sid, ssid, alpha)
    K = key_ex_s(p_s, x_s, P_u, X_u, X_s, id_s, id_u, ssidp)
    SK = f(K, 0, ssidp)
    A_s = f(K, 1, ssidp)

    # Send beta, X_s, c and A_s and send it to the client.
    send(beta=beta, X_s=X_s, c=c, A_s=A_s)

    # Receive A_u from the client.
    data = recv()
    A_u = j2b(data['A_u'])

    # Compute A_u and verify it equals the one received from the client.
    if A_u != f(K, 2, ssidp):
        return (None, sid, ssid)

    return (SK, sid, ssid)
