export type RoutingTier = "standard" | "degraded";

export type AdmissionAllowResult = {
  outcome: "admitted";
  requestId: string;
  degraded?: boolean;
};

/**
 * Client body / header keys that must never influence gateway routing (§4.3.7).
 * Adapter ingress does not read these; they are listed so wire-boundary tests can
 * prove injection attempts are ignored.
 */
export const CLIENT_ROUTING_INJECTION_KEYS = [
  "routing_tier",
  "degraded",
  "degraded_notice",
] as const;

export type ClientRoutingInjectionKey =
  (typeof CLIENT_ROUTING_INJECTION_KEYS)[number];

/** True when a parsed request body carries any prohibited routing injection key. */
export function bodyHasClientRoutingInjection(
  body: Record<string, unknown>,
): boolean {
  return CLIENT_ROUTING_INJECTION_KEYS.some((key) =>
    Object.prototype.hasOwnProperty.call(body, key),
  );
}

export function routingTierFromAdmission(
  admission: AdmissionAllowResult,
): RoutingTier {
  return admission.degraded ? "degraded" : "standard";
}

export function degradedNoticeFromAdmission(
  admission: AdmissionAllowResult,
): boolean | undefined {
  if (admission.degraded) {
    return true;
  }
  return undefined;
}

/** Gateway-only: routing tier is derived solely from the admission answer. */
export function resolveRoutingTier(
  admission: AdmissionAllowResult,
): RoutingTier {
  return routingTierFromAdmission(admission);
}
