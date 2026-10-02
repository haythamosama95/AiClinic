import { base64UrlEncode } from "../base64url.js";
import { sha256Hex } from "../canonical.js";
import { operationChallenge } from "../operation.js";
import {
  derEcdsaRawToDer,
  type Assertion,
} from "../webauthn.js";
import { TESTKIT_MARKER } from "./index.js";

const textEncoder = new TextEncoder();

async function rpIdHashBytes(rpId: string): Promise<Uint8Array> {
  const hex = await sha256Hex(textEncoder.encode(rpId));
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = Number.parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

function buildAuthenticatorData(
  rpIdHash: Uint8Array,
  up: boolean,
  uv: boolean,
): Uint8Array {
  let flags = 0;
  if (up) {
    flags |= 0x01;
  }
  if (uv) {
    flags |= 0x04;
  }
  const data = new Uint8Array(37);
  data.set(rpIdHash, 0);
  data[32] = flags;
  return data;
}

async function exportEs256Spki(publicKey: CryptoKey): Promise<Uint8Array> {
  const spki = await crypto.subtle.exportKey("spki", publicKey);
  return new Uint8Array(spki);
}

async function exportEd25519Raw(publicKey: CryptoKey): Promise<Uint8Array> {
  const raw = await crypto.subtle.exportKey("raw", publicKey);
  return new Uint8Array(raw);
}

export async function createSoftwareAuthenticator(
  alg: "ES256" | "EdDSA",
): Promise<{
  attest(): Promise<{ alg: "ES256" | "EdDSA"; publicKey: Uint8Array }>;
  assert(input: {
    operation: unknown;
    rpId: string;
    origin: string;
    up: boolean;
    uv: boolean;
  }): Promise<Assertion>;
}> {
  void TESTKIT_MARKER;

  if (alg === "ES256") {
    const pair = await crypto.subtle.generateKey(
      { name: "ECDSA", namedCurve: "P-256" },
      true,
      ["sign", "verify"],
    );
    return {
      async attest() {
        void TESTKIT_MARKER;
        return {
          alg: "ES256",
          publicKey: await exportEs256Spki(pair.publicKey),
        };
      },
      async assert(input) {
        void TESTKIT_MARKER;
        const challenge = await operationChallenge(input.operation);
        const clientDataJSON = textEncoder.encode(
          JSON.stringify({
            type: "webauthn.get",
            challenge,
            origin: input.origin,
          }),
        );
        const rpHash = await rpIdHashBytes(input.rpId);
        const authenticatorData = buildAuthenticatorData(
          rpHash,
          input.up,
          input.uv,
        );
        const clientDataHashHex = await sha256Hex(clientDataJSON);
        const clientDataHash = new Uint8Array(clientDataHashHex.length / 2);
        for (let i = 0; i < clientDataHash.length; i++) {
          clientDataHash[i] = Number.parseInt(
            clientDataHashHex.slice(i * 2, i * 2 + 2),
            16,
          );
        }
        const signedData = new Uint8Array(
          authenticatorData.byteLength + clientDataHash.byteLength,
        );
        signedData.set(authenticatorData, 0);
        signedData.set(clientDataHash, authenticatorData.byteLength);
        const rawSig = new Uint8Array(
          await crypto.subtle.sign(
            { name: "ECDSA", hash: "SHA-256" },
            pair.privateKey,
            signedData,
          ),
        );
        return {
          alg: "ES256",
          authenticatorData,
          clientDataJSON,
          signature: derEcdsaRawToDer(rawSig),
        };
      },
    };
  }

  const pair = await crypto.subtle.generateKey(
    { name: "Ed25519" },
    true,
    ["sign", "verify"],
  );
  return {
    async attest() {
      void TESTKIT_MARKER;
      return {
        alg: "EdDSA",
        publicKey: await exportEd25519Raw(pair.publicKey),
      };
    },
    async assert(input) {
      void TESTKIT_MARKER;
      const challenge = await operationChallenge(input.operation);
      const clientDataJSON = textEncoder.encode(
        JSON.stringify({
          type: "webauthn.get",
          challenge,
          origin: input.origin,
        }),
      );
      const rpHash = await rpIdHashBytes(input.rpId);
      const authenticatorData = buildAuthenticatorData(
        rpHash,
        input.up,
        input.uv,
      );
      const clientDataHashHex = await sha256Hex(clientDataJSON);
      const clientDataHash = new Uint8Array(clientDataHashHex.length / 2);
      for (let i = 0; i < clientDataHash.length; i++) {
        clientDataHash[i] = Number.parseInt(
          clientDataHashHex.slice(i * 2, i * 2 + 2),
          16,
        );
      }
      const signedData = new Uint8Array(
        authenticatorData.byteLength + clientDataHash.byteLength,
      );
      signedData.set(authenticatorData, 0);
      signedData.set(clientDataHash, authenticatorData.byteLength);
      const signature = new Uint8Array(
        await crypto.subtle.sign("Ed25519", pair.privateKey, signedData),
      );
      return {
        alg: "EdDSA",
        authenticatorData,
        clientDataJSON,
        signature,
      };
    },
  };
}
