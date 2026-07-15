// autocannon (devDependency, test-tooling only) ships no type definitions.
// Minimal ambient shape for the small subset used in tests/performance.
declare module "autocannon" {
  interface AutocannonOptions {
    url: string
    connections?: number
    duration?: number
    amount?: number
  }
  interface AutocannonResult {
    non2xx: number
    errors: number
    [key: string]: unknown
  }
  function autocannon(opts: AutocannonOptions): Promise<AutocannonResult>
  export default autocannon
}
