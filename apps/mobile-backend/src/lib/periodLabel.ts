const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

interface PeriodSource {
  billPeriodId?: string | null
  billYear?: number | null
  billMonth?: number | null
  title?: string | null
  period?: string | null
}

// Bills/receipts/transactions imported from different eras carry different
// period fields (billPeriodId "YYYY-MM" vs billYear+billMonth vs a free-text
// title/period string on hand-created records) — this gives every caller one
// human-readable label regardless of source, instead of each screen doing
// its own `bill['title'] ?? bill['period']` fallback chain (which produces
// literal "null" text when both are actually absent).
export function periodLabelFrom(source: PeriodSource): string {
  if (source.billPeriodId && /^\d{4}-\d{2}$/.test(source.billPeriodId)) {
    const [year, month] = source.billPeriodId.split("-").map(Number)
    if (month >= 1 && month <= 12) return `${MONTHS[month - 1]} ${year}`
  }
  if (source.billYear && source.billMonth && source.billMonth >= 1 && source.billMonth <= 12) {
    return `${MONTHS[source.billMonth - 1]} ${source.billYear}`
  }
  return source.title ?? source.period ?? "Bill"
}
