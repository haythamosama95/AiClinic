/** Validate channel metadata before a DO reply can reach business logic. */
export function decodeDoResponse<T>(
  value: unknown,
  sentVersion: number,
): T | undefined {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return undefined;
  }
  const response = value as Record<string, unknown>;
  if (
    !Number.isInteger(response.contract_version) ||
    response.contract_version !== sentVersion ||
    response.code === "contract_version_unsupported"
  ) {
    return undefined;
  }
  return response as unknown as T;
}
