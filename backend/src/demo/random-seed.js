export class SeededRandom {
  constructor(seed) { this.state = BigInt.asUintN(64, BigInt(seed)); }
  next() { this.state = BigInt.asUintN(64, this.state * 6364136223846793005n + 1442695040888963407n); return Number(this.state >> 11n) / 9007199254740992; }
  int(max) { return Math.floor(this.next() * max); }
  range(min, max) { return min + this.next() * (max - min); }
  pick(values) { return values[this.int(values.length)]; }
  chance(probability) { return this.next() < probability; }
  date(start, end) { return new Date(start.getTime() + this.next() * (end.getTime() - start.getTime())); }
}
