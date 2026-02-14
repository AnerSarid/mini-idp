/**
 * Shared TTL (time-to-live) parsing utilities.
 *
 * Used by both the `create` and `extend` commands to convert
 * compact TTL strings like "7d" or "24h" into typed values
 * compatible with dayjs `.add()`.
 */

export type TtlUnit = 'day' | 'hour';

const TTL_REGEX = /^\d+[dh]$/;

/**
 * Validate that a string is a well-formed TTL expression.
 * @returns The validated TTL string (pass-through).
 * @throws If the format is invalid.
 */
export function validateTtl(ttl: string): string {
  if (!TTL_REGEX.test(ttl)) {
    throw new Error(
      'TTL must be a number followed by d (days) or h (hours). Example: 7d, 24h'
    );
  }
  return ttl;
}

/**
 * Parse a compact TTL string into a numeric value and a dayjs-compatible unit.
 *
 * Examples:
 *   parseTtl("7d")  → { value: 7,  unit: "day"  }
 *   parseTtl("24h") → { value: 24, unit: "hour" }
 */
export function parseTtl(ttl: string): { value: number; unit: TtlUnit } {
  const value = parseInt(ttl.slice(0, -1), 10);
  const unit: TtlUnit = ttl.slice(-1) === 'd' ? 'day' : 'hour';
  return { value, unit };
}
