// Plain-object builder matching the SocietySchema shape in src/models/index.ts.
export function makeSociety(overrides: Record<string, unknown> = {}) {
  return {
    name: "Sunrise Complex",
    address: "456 Park Avenue, Pune, Maharashtra 411001",
    fyStartMonth: 4,
    gstNo: "27FGHIJ5678G2Y6",
    ...overrides,
  }
}
