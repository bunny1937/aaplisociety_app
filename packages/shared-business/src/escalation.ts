import { DeliveryChannel } from "@aapli/constants"

// Escalation ladder ported from lib/escalation.js / Visitor.EscalationStep
export interface EscalationLevel { level: number; afterSeconds: number; channels: DeliveryChannel[] }

export const VISITOR_ESCALATION_LADDER: EscalationLevel[] = [
  { level: 1, afterSeconds: 0,   channels: ["in_app", "push"] },
  { level: 2, afterSeconds: 60,  channels: ["push", "sms"] },
  { level: 3, afterSeconds: 180, channels: ["whatsapp", "guard_call"] },
  { level: 4, afterSeconds: 300, channels: ["admin_alert"] },
]

export function nextEscalation(currentLevel: number): EscalationLevel | null {
  return VISITOR_ESCALATION_LADDER.find((l) => l.level === currentLevel + 1) ?? null
}
