export class ProgressReporter {
  constructor(enabled = true) { this.enabled = enabled; this.startedAt = Date.now(); }
  phase(name, count) { if (this.enabled) console.log(`[demo] ${name}: ${count.toLocaleString()} records`); }
  complete() { if (this.enabled) console.log(`[demo] completed in ${((Date.now() - this.startedAt) / 1000).toFixed(1)}s`); }
}
