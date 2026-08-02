export type RoutingTier = "standard" | "degraded";

export type AdmissionAllowResult = {
  outcome: "admitted";
  requestId: string;
  degraded?: boolean;
};

export type ClientRoutingInjection = {
  routing_tier?: string;
  degraded?: boolean;
  degraded_notice?: boolean;
};

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

export function resolveRoutingTier(
  admission: AdmissionAllowResult,
  _clientInjection: ClientRoutingInjection = {},
): RoutingTier {
  return routingTierFromAdmission(admission);
}
