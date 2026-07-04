"""JWT token helpers for auth contract tests."""

from __future__ import annotations

import time
from typing import Any

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

_TEST_RSA_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
_TEST_RSA_PUBLIC = _TEST_RSA_KEY.public_key()
_TEST_KID = "test-rsa-key"


def test_rsa_private_pem() -> bytes:
    return _TEST_RSA_KEY.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )


def jwks_document() -> dict[str, Any]:
    """JWKS document for the in-test RSA key pair."""
    from jwt.algorithms import RSAAlgorithm

    jwk = RSAAlgorithm.to_jwk(_TEST_RSA_PUBLIC, as_dict=True)
    jwk["kid"] = _TEST_KID
    jwk["use"] = "sig"
    jwk["alg"] = "RS256"
    return {"keys": [jwk]}


def make_hs256_token(
    secret: str,
    *,
    staff_role: str = "doctor",
    staff_id: str = "staff-001",
    exp_delta_s: int = 3600,
    nbf_delta_s: int = 0,
    extra_claims: dict[str, Any] | None = None,
) -> str:
    now = int(time.time())
    payload: dict[str, Any] = {
        "sub": staff_id,
        "staff_role": staff_role,
        "exp": now + exp_delta_s,
    }
    if nbf_delta_s != 0:
        payload["nbf"] = now + nbf_delta_s
    if extra_claims:
        payload.update(extra_claims)
    return jwt.encode(payload, secret, algorithm="HS256")


def make_rs256_token(
    *,
    staff_role: str = "doctor",
    staff_id: str = "staff-001",
    exp_delta_s: int = 3600,
    nbf_delta_s: int = 0,
    extra_claims: dict[str, Any] | None = None,
) -> str:
    now = int(time.time())
    payload: dict[str, Any] = {
        "sub": staff_id,
        "staff_role": staff_role,
        "exp": now + exp_delta_s,
    }
    if nbf_delta_s != 0:
        payload["nbf"] = now + nbf_delta_s
    if extra_claims:
        payload.update(extra_claims)
    headers = {"kid": _TEST_KID}
    return jwt.encode(
        payload,
        test_rsa_private_pem(),
        algorithm="RS256",
        headers=headers,
    )


def tamper_token(token: str) -> str:
    """Corrupt the payload segment so signature verification fails."""
    parts = token.split(".")
    if len(parts) != 3 or not parts[1]:
        return token + "x"
    payload = parts[1]
    flipped = "A" if payload[len(payload) // 2] != "A" else "B"
    parts[1] = payload[: len(payload) // 2] + flipped + payload[len(payload) // 2 + 1 :]
    return ".".join(parts)
