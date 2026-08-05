export type OperatorPrincipal = {
  operatorId: string;
};

/** Port seam resolving an operator principal or rejecting (Clarification Q2). */
export type OperatorAuth = {
  resolve(request: Request): OperatorPrincipal | null;
};

export type ControlBindings = {
  DB: D1Database;
  R2?: R2Bucket;
};

export type EnrollPayload = {
  org_id: string;
  display_name: string;
  region: string;
  plan: string;
  public_key: string;
  algorithm: string;
  kid: string;
};

export type RotatePayload = {
  kid: string;
  public_key: string;
  algorithm: string;
};

export type DeprecatePayload = {
  successor_id: string;
};

export type CapabilityRoute = {
  capabilityId: string;
  version: string;
  action: "deprecate" | "retire";
};

export type CohortPayload = {
  installation_ids: string[];
  cohort_name?: string;
};

export type PublishPayload = {
  document: Record<string, unknown>;
};

export type CohortCapabilityRoute = {
  capabilityId: string;
  version: string;
  action: "activate" | "promote";
};

export type RoutingPolicyRoute = {
  policyId: string;
  version: string;
  action: "publish" | "canary" | "promote" | "rollback";
};

export type TokenContractBeginPayload = {
  ver: string;
};

export type TokenContractRetirePayload = {
  ver: string;
};
