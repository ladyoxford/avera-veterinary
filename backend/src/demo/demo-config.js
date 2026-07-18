export const generatorVersion = '1.0.0';

const base = {
  years: 10,
  batchSize: 500,
  media: true,
  inventoryMovements: 0,
  prescriptions: 0,
  schedules: 0,
  payments: 0,
};

export const datasetSizes = {
  small: { ...base, clinics: 1, staff: 10, owners: 160, patients: 200, consultations: 1000, invoices: 300, laboratoryReports: 200, vaccinations: 150, hospitalizations: 30, surgeries: 20, inventoryProducts: 200, inventoryMovements: 1000, prescriptions: 250, schedules: 350, payments: 180, mediaAssets: 120 },
  medium: { ...base, clinics: 3, staff: 25, owners: 800, patients: 1000, consultations: 8000, invoices: 3000, laboratoryReports: 1500, vaccinations: 800, hospitalizations: 200, surgeries: 100, inventoryProducts: 500, inventoryMovements: 8000, prescriptions: 2200, schedules: 1800, payments: 1000, mediaAssets: 600 },
  large: { ...base, clinics: 15, staff: 100, owners: 4000, patients: 5000, consultations: 50000, invoices: 15000, laboratoryReports: 8000, vaccinations: 3000, hospitalizations: 1000, surgeries: 500, inventoryProducts: 1500, inventoryMovements: 30000, prescriptions: 12000, schedules: 8000, payments: 5000, mediaAssets: 3000 },
  enterprise: { ...base, clinics: 15, staff: 100, owners: 20000, patients: 25000, consultations: 250000, invoices: 100000, laboratoryReports: 40000, vaccinations: 15000, hospitalizations: 5000, surgeries: 2500, inventoryProducts: 5000, inventoryMovements: 300000, prescriptions: 60000, schedules: 50000, payments: 40000, mediaAssets: 15000 },
};

export function parseDemoOptions(argv) {
  const flags = Object.fromEntries(argv.filter((value) => value.startsWith('--')).map((value) => {
    const [key, raw = 'true'] = value.slice(2).split('=');
    return [key, raw];
  }));
  const size = flags.size ?? 'small';
  if (!datasetSizes[size]) throw new Error(`Unknown demo dataset size: ${size}.`);
  if (size === 'enterprise' && flags['confirm-enterprise'] !== 'true') {
    throw new Error('Enterprise generation requires --confirm-enterprise=true.');
  }
  const config = { ...datasetSizes[size] };
  const numericKeys = ['clinics', 'staff', 'owners', 'patients', 'consultations', 'invoices', 'laboratoryReports', 'vaccinations', 'hospitalizations', 'surgeries', 'inventoryProducts', 'inventoryMovements', 'prescriptions', 'schedules', 'payments', 'mediaAssets', 'years', 'batchSize'];
  for (const key of numericKeys) if (flags[key] != null) config[key] = Number(flags[key]);
  if (Object.values(config).some((value) => typeof value === 'number' && (!Number.isFinite(value) || value < 0))) throw new Error('Demo generation counts must be non-negative numbers.');
  return { size, config, seed: Number(flags.seed ?? 2026), reset: flags.reset === 'true', dryRun: flags['dry-run'] === 'true', media: flags.media !== 'false', preserve: flags.preserve !== 'false' };
}
