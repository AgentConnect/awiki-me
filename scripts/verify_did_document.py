"""Validate awiki-compatible DID document and W3C proof.

Usage:
  uv run python scripts/verify_did_document.py --input /path/to/did_document.json
  uv run python scripts/verify_did_document.py --input /path/to/register_payload.json --from-register-payload
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
from pathlib import Path
from typing import Any

from cryptography.hazmat.primitives.asymmetric import ec

from anp.proof import verify_w3c_proof


def _b64url_decode(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(value + padding)


def _b64url_encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _extract_key1_vm(did_doc: dict[str, Any]) -> dict[str, Any]:
    for vm in did_doc.get("verificationMethod", []):
        if not isinstance(vm, dict):
            continue
        if vm.get("type") != "EcdsaSecp256k1VerificationKey2019":
            continue
        vm_id = vm.get("id", "")
        if isinstance(vm_id, str) and vm_id.endswith("#key-1"):
            return vm
    raise ValueError("Missing verificationMethod #key-1 with secp256k1 type.")


def _jwk_to_secp256k1_public_key(jwk: dict[str, Any]) -> ec.EllipticCurvePublicKey:
    if jwk.get("kty") != "EC" or jwk.get("crv") != "secp256k1":
        raise ValueError(f"Unexpected JWK kty/crv: {jwk.get('kty')}/{jwk.get('crv')}")
    x = int.from_bytes(_b64url_decode(str(jwk["x"])), "big")
    y = int.from_bytes(_b64url_decode(str(jwk["y"])), "big")
    return ec.EllipticCurvePublicNumbers(x=x, y=y, curve=ec.SECP256K1()).public_key()


def _compute_jwk_thumbprint(jwk: dict[str, Any]) -> str:
    canonical = (
        f'{{"crv":"secp256k1","kty":"EC","x":"{jwk["x"]}","y":"{jwk["y"]}"}}'
    )
    digest = hashlib.sha256(canonical.encode("ascii")).digest()
    return _b64url_encode(digest)


def _validate_did_fingerprint_binding(did_doc: dict[str, Any], key1_jwk: dict[str, Any]) -> None:
    did = str(did_doc.get("id", ""))
    match = re.match(r"^did:wba:[^:]+:[^:]+:k1_([A-Za-z0-9_-]{43})$", did)
    if not match:
        raise ValueError(f"DID format mismatch: {did}")
    did_fp = match.group(1)
    actual_fp = _compute_jwk_thumbprint(key1_jwk)
    if did_fp != actual_fp:
        raise ValueError(
            "DID key fingerprint mismatch: "
            f"did={did_fp}, computed={actual_fp}. This will fail awiki key-binding check."
        )


def _validate_proof_shape(did_doc: dict[str, Any]) -> dict[str, Any]:
    proof = did_doc.get("proof")
    if not isinstance(proof, dict):
        raise ValueError("Missing proof object.")
    required = ["type", "created", "verificationMethod", "proofPurpose", "proofValue"]
    missing = [k for k in required if not proof.get(k)]
    if missing:
        raise ValueError(f"Proof missing required fields: {', '.join(missing)}")
    if proof["type"] != "EcdsaSecp256k1Signature2019":
        raise ValueError(f"Unsupported proof type: {proof['type']}")
    if proof["proofPurpose"] != "authentication":
        raise ValueError(f"Unexpected proofPurpose: {proof['proofPurpose']}")
    return proof


def _load_doc(path: Path, from_register_payload: bool) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if from_register_payload:
        did_doc = data.get("did_document")
        if not isinstance(did_doc, dict):
            raise ValueError("Input payload missing did_document field.")
        return did_doc
    if not isinstance(data, dict):
        raise ValueError("Input JSON must be an object.")
    return data


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate DID document compatibility for awiki.")
    parser.add_argument("--input", required=True, help="Path to did_document JSON file.")
    parser.add_argument(
        "--from-register-payload",
        action="store_true",
        help="Input file is a register payload with top-level did_document field.",
    )
    args = parser.parse_args()

    did_doc = _load_doc(Path(args.input), from_register_payload=args.from_register_payload)
    key1_vm = _extract_key1_vm(did_doc)
    key1_jwk = key1_vm.get("publicKeyJwk")
    if not isinstance(key1_jwk, dict):
        raise ValueError("verificationMethod #key-1 missing publicKeyJwk.")
    proof = _validate_proof_shape(did_doc)
    _validate_did_fingerprint_binding(did_doc, key1_jwk)

    public_key = _jwk_to_secp256k1_public_key(key1_jwk)
    verified = verify_w3c_proof(
        document=did_doc,
        public_key=public_key,
        expected_purpose="authentication",
        expected_domain=proof.get("domain"),
        expected_challenge=proof.get("challenge"),
    )
    if not verified:
        raise ValueError("W3C proof signature verification failed.")

    print("OK: DID document passed key-binding + W3C proof verification.")
    print(f"DID: {did_doc['id']}")
    print(f"proof.created: {proof.get('created')}")
    print(f"proof.domain: {proof.get('domain')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
