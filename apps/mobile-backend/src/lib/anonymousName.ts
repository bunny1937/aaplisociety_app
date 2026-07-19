// Mirrors web's lib/complaintUtils.js generateAnonymousName() so mobile- and
// web-created complaints render consistently — same style pseudonym, not
// tied to the real member ("anonymous" is a display concept only; memberId
// is always stored/required regardless, matching web's own behavior).
const ADJECTIVES = [
  "Velvet", "Lunar", "Silent", "Amber", "Cobalt", "Iron", "Silver", "Golden",
  "Crimson", "Jade", "Neon", "Rustic", "Marble", "Shadow", "Crystal", "Ashen",
  "Blazing", "Frosted", "Misty", "Storm",
]
const NOUNS = [
  "Tiger", "Echo", "Circuit", "Falcon", "Phoenix", "River", "Prism", "Ridge",
  "Vortex", "Cipher", "Ember", "Specter", "Nexus", "Orbit", "Pulse", "Torch",
  "Haven", "Maze", "Signal", "Drift",
]

export function generateAnonymousName(): string {
  const adj = ADJECTIVES[Math.floor(Math.random() * ADJECTIVES.length)]
  const noun = NOUNS[Math.floor(Math.random() * NOUNS.length)]
  const suffix = Math.floor(Math.random() * 90 + 10) // 10-99
  return `${adj}${noun}${suffix}`
}
