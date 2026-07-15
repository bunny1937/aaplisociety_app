import { describe, it, expect } from "vitest"
import { periodLabelFrom } from "../../src/lib/periodLabel.js"

describe("periodLabelFrom", () => {
  it("formats a billPeriodId (YYYY-MM) as 'Mon YYYY'", () => {
    expect(periodLabelFrom({ billPeriodId: "2026-05" })).toBe("May 2026")
  })

  it("falls back to billYear/billMonth when billPeriodId is absent", () => {
    expect(periodLabelFrom({ billYear: 2026, billMonth: 4 })).toBe("Apr 2026")
  })

  it("prefers billPeriodId over billYear/billMonth when both present", () => {
    expect(periodLabelFrom({ billPeriodId: "2026-05", billYear: 2026, billMonth: 4 })).toBe("May 2026")
  })

  it("falls back to title, then period, then 'Bill' when no period fields exist", () => {
    expect(periodLabelFrom({ title: "Q2 Maintenance" })).toBe("Q2 Maintenance")
    expect(periodLabelFrom({ period: "2026-Q2" })).toBe("2026-Q2")
    expect(periodLabelFrom({})).toBe("Bill")
  })

  it("ignores a malformed billPeriodId instead of throwing", () => {
    expect(periodLabelFrom({ billPeriodId: "not-a-period", period: "2026-Q2" })).toBe("2026-Q2")
  })
})
