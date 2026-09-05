export type { OperatorAuth, OperatorPrincipal } from "./types";
export { createSecretOperatorAuth } from "./auth";
export {
  handleDelete,
  handleEnroll,
  handleResume,
  handleRevokeKey,
  handleRotate,
  handleSuspend,
} from "./lifecycle";
export { handleEntitle } from "./entitle";
export { handleDeprecate, handleRetire } from "./capability-lifecycle";
export { handleCohortActivate, handleCohortPromote } from "./cohort";
export {
  handleRoutingPolicyCanary,
  handleRoutingPolicyPromote,
  handleRoutingPolicyPublish,
  handleRoutingPolicyRollback,
} from "./routing-policy";
export {
  handleTokenContractBeginRotation,
  handleTokenContractRetire,
} from "./token-contract";
export {
  handleInstallationPurge,
  handleSupportLookup,
} from "./support-purge";
export { handleInstallationQuotaGet } from "./quota-inspect";
export { handleKillSwitchArm, handleKillSwitchDisarm } from "./kill-switch";

import {
  handleDeprecate,
  handleRetire,
  parseCapabilityRoute,
} from "./capability-lifecycle";
import {
  handleCohortActivate,
  handleCohortPromote,
  parseCohortCapabilityRoute,
} from "./cohort";
import { handleEntitle } from "./entitle";
import { reject } from "./http";
import {
  handleDelete,
  handleEnroll,
  handleResume,
  handleRevokeKey,
  handleRotate,
  handleSuspend,
} from "./lifecycle";
import {
  handleRoutingPolicyCanary,
  handleRoutingPolicyPromote,
  handleRoutingPolicyPublish,
  handleRoutingPolicyRollback,
  parseRoutingPolicyRoute,
} from "./routing-policy";
import {
  handleInstallationPurge,
  handleSupportLookup,
} from "./support-purge";
import { handleInstallationQuotaGet } from "./quota-inspect";
import { handleKillSwitchArm, handleKillSwitchDisarm } from "./kill-switch";
import {
  handleTokenContractBeginRotation,
  handleTokenContractRetire,
} from "./token-contract";
import type { ControlBindings, OperatorAuth } from "./types";
import { noopLogger, type Logger } from "../logger";

const CONTROL_ACTION_PATTERN =
  /^\/control\/installations\/[^/]+\/(enroll|rotate|revoke-key|suspend|resume|delete|purge|entitle)$/;

const CAPABILITY_LIFECYCLE_PATTERN =
  /^\/control\/capabilities\/[^/]+\/versions\/[^/]+\/(deprecate|retire)$/;

const TOKEN_CONTRACT_PATTERN =
  /^\/control\/token-contract\/(begin-rotation|retire)$/;

const SUPPORT_LOOKUP_PATTERN = /^\/control\/support\/lookup$/;

const QUOTA_INSPECT_PATTERN = /^\/control\/installations\/[^/]+\/quota$/;

const ROUTING_POLICY_PUBLISH_PATTERN = /^\/control\/routing-policies\/publish$/;
const ROUTING_POLICY_VERSIONED_PATTERN =
  /^\/control\/routing-policies\/[^/]+\/versions\/[^/]+\/(canary|promote|rollback)$/;

const COHORT_CAPABILITY_PATTERN =
  /^\/control\/capabilities\/[^/]+\/versions\/[^/]+\/(activate|promote)$/;

const KILL_SWITCH_PATTERN = /^\/control\/kill-switches\/(arm|disarm)$/;

export function isQuotaInspectRoute(pathname: string): boolean {
  return QUOTA_INSPECT_PATTERN.test(pathname);
}

export function isControlRoute(pathname: string): boolean {
  return (
    CONTROL_ACTION_PATTERN.test(pathname) ||
    CAPABILITY_LIFECYCLE_PATTERN.test(pathname) ||
    COHORT_CAPABILITY_PATTERN.test(pathname) ||
    ROUTING_POLICY_PUBLISH_PATTERN.test(pathname) ||
    ROUTING_POLICY_VERSIONED_PATTERN.test(pathname) ||
    TOKEN_CONTRACT_PATTERN.test(pathname) ||
    SUPPORT_LOOKUP_PATTERN.test(pathname) ||
    QUOTA_INSPECT_PATTERN.test(pathname) ||
    KILL_SWITCH_PATTERN.test(pathname)
  );
}

export async function dispatchControlRequest(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
  logger: Logger = noopLogger,
): Promise<Response> {
  const pathname = new URL(request.url).pathname;
  const action = pathname.split("/").pop() ?? pathname;

  logger.debug("control_request_received", { pathname, action });

  if (SUPPORT_LOOKUP_PATTERN.test(pathname)) {
    return handleSupportLookup(request, bindings, operatorAuth);
  }

  if (QUOTA_INSPECT_PATTERN.test(pathname)) {
    return handleInstallationQuotaGet(request, bindings, operatorAuth);
  }

  if (CAPABILITY_LIFECYCLE_PATTERN.test(pathname)) {
    const route = parseCapabilityRoute(request);
    if (!route) {
      return reject(400, "invalid_route");
    }
    if (route.action === "deprecate") {
      return handleDeprecate(request, bindings, operatorAuth);
    }
    return handleRetire(request, bindings, operatorAuth);
  }

  if (COHORT_CAPABILITY_PATTERN.test(pathname)) {
    const route = parseCohortCapabilityRoute(request);
    if (!route) {
      return reject(400, "invalid_route");
    }
    if (route.action === "activate") {
      return handleCohortActivate(request, bindings, operatorAuth);
    }
    return handleCohortPromote(request, bindings, operatorAuth);
  }

  if (ROUTING_POLICY_PUBLISH_PATTERN.test(pathname)) {
    return handleRoutingPolicyPublish(request, bindings, operatorAuth);
  }

  if (ROUTING_POLICY_VERSIONED_PATTERN.test(pathname)) {
    const route = parseRoutingPolicyRoute(request);
    if (!route) {
      return reject(400, "invalid_route");
    }
    if (route.action === "canary") {
      return handleRoutingPolicyCanary(request, bindings, operatorAuth);
    }
    if (route.action === "promote") {
      return handleRoutingPolicyPromote(request, bindings, operatorAuth);
    }
    return handleRoutingPolicyRollback(request, bindings, operatorAuth);
  }

  if (TOKEN_CONTRACT_PATTERN.test(pathname)) {
    const action = pathname.split("/").pop();
    if (action === "begin-rotation") {
      return handleTokenContractBeginRotation(request, bindings, operatorAuth);
    }
    if (action === "retire") {
      return handleTokenContractRetire(request, bindings, operatorAuth);
    }
    return reject(400, "invalid_route");
  }

  if (KILL_SWITCH_PATTERN.test(pathname)) {
    const action = pathname.split("/").pop();
    if (action === "arm") {
      return handleKillSwitchArm(request, bindings, operatorAuth);
    }
    if (action === "disarm") {
      return handleKillSwitchDisarm(request, bindings, operatorAuth);
    }
    return reject(400, "invalid_route");
  }

  const installAction = pathname.split("/").pop();

  switch (installAction) {
    case "enroll":
      return handleEnroll(request, bindings, operatorAuth);
    case "rotate":
      return handleRotate(request, bindings, operatorAuth);
    case "revoke-key":
      return handleRevokeKey(request, bindings, operatorAuth);
    case "suspend":
      return handleSuspend(request, bindings, operatorAuth);
    case "resume":
      return handleResume(request, bindings, operatorAuth);
    case "delete":
      return handleDelete(request, bindings, operatorAuth);
    case "purge":
      return handleInstallationPurge(request, bindings, operatorAuth);
    case "entitle":
      return handleEntitle(request, bindings, operatorAuth);
    default:
      // Fires only if an action is added to the route pattern without a handler; defensive.
      logger.debug("control_route_not_found", { pathname });
      return new Response("Not Found", { status: 404 });
  }
}
