/**
 * Fixture: domain module illegally imports the Paymob adapter (E2E-P4.2-09).
 */

import { createCheckout } from "../../../../src/provider/paymob/adapter.js";

export const boundaryViolation = createCheckout;
