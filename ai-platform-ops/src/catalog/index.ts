import { CLINIC_ENTITIES } from "./clinic";
import { CONTROL_ENTITIES } from "./control";
import { DEBUG_ENTITIES } from "./debug";
import { E2E_ENTITIES } from "./e2e";
import { SETUP_ENTITIES } from "./setup";
export { SETUP_STEPS } from "./setup";
export type { SetupStep } from "./setup";
import type { CategoryId, EntityDef } from "./types";
export { CATEGORIES } from "./types";
export type { CategoryId, EntityDef, FieldDef, BuiltRequest } from "./types";

export const ALL_ENTITIES: EntityDef[] = [
  ...SETUP_ENTITIES,
  ...CLINIC_ENTITIES,
  ...CONTROL_ENTITIES,
  ...DEBUG_ENTITIES,
  ...E2E_ENTITIES,
];

export function entitiesForCategory(category: CategoryId): EntityDef[] {
  return ALL_ENTITIES.filter((e) => e.category === category);
}

export function entityById(id: string): EntityDef | undefined {
  return ALL_ENTITIES.find((e) => e.id === id);
}
