import { randomUUID } from 'node:crypto';
import { hashPassword } from '../security/passwords.js';
import { generatorVersion } from './demo-config.js';
import { SeededRandom } from './random-seed.js';
import { ProgressReporter } from './progress-reporter.js';
import { validateDemoDataset } from './validation.js';

const firstNames = ['Ada','Amina','Chinedu','Emmanuel','Fatima','Grace','Ifeanyi','Kemi','Musa','Nneka','Olu','Tari','Uche','Yemi','Zainab'];
const lastNames = ['Adeyemi','Bello','Chukwu','Danladi','Eze','Ibrahim','Okafor','Olawale','Sule','Yakubu'];
const clinicKinds = ['Small-animal clinic','Mixed-practice clinic','Livestock hospital','Emergency hospital','Referral hospital','Equine clinic','Farm-animal practice','Veterinary diagnostic centre'];
const roleNames = ['Clinic Administrator','Veterinarian','Veterinary Nurse','Receptionist','Laboratory Staff','Pharmacist','Cashier','Practice Manager','Inventory Officer','Accountant','Surgeon','Diagnostic Imaging Staff'];
const species = [
  ['Dog', .45, ['Mixed Breed','German Shepherd','Labrador Retriever','Rottweiler','Boerboel']], ['Cat', .20, ['Domestic Shorthair','Persian','Siamese']], ['Goat', .10, ['West African Dwarf','Boer','Sahel']], ['Sheep', .06, ['Yankasa','Balami','Uda']], ['Cattle', .07, ['Bunaji','White Fulani','Friesian']], ['Rabbit', .05, ['New Zealand White','Dutch','Californian']], ['Bird', .04, ['African Grey','Layer Hen','Broiler']], ['Horse', .02, ['West African Barb','Thoroughbred']], ['Exotic', .01, ['Tortoise','Guinea Pig','Ferret']],
];
const smallAnimalDiagnoses = ['Routine wellness','Vaccination','Parvovirus','Ehrlichiosis','Babesiosis','Mange','Otitis','Gastroenteritis','Pyometra','Wound treatment','Fracture','Tick infestation','Skin disease','Urinary disease','Kidney disease','Liver disease','Respiratory disease','Pregnancy diagnosis','Dental care','Eye disease','Ascites'];
const farmDiagnoses = ['PPR','Orf','Mastitis','Bloat','Trypanosomiasis','Helminthiasis','Lameness','Ketosis','CBPP suspicion','Respiratory disease','Wound treatment','Reproductive examination','Retained placenta','Dystocia','Herd-health visit','Vaccination campaign','Deworming programme'];
const products = ['Amoxicillin','Doxycycline','Ivermectin','Albendazole','Meloxicam','Ketamine','Xylazine','Hartmanns Fluid','Rabies Vaccine','DHPP Vaccine','FVRCP Vaccine','Suture Pack','Gauze','Blood Collection Tube','Disinfectant','Vitamin Supplement'];
const vaccineBySpecies = { Dog: ['DHPP','Rabies'], Cat: ['FVRCP','Rabies'], Goat: ['PPR','Clostridial Vaccine'], Sheep: ['PPR','Clostridial Vaccine'], Cattle: ['CBPP Vaccine','Clostridial Vaccine'], Rabbit: ['Rabbit Haemorrhagic Disease Vaccine'], Bird: ['Newcastle Disease Vaccine'], Horse: ['Tetanus Vaccine'], Exotic: ['Species-specific wellness vaccine'] };

export async function generateDemoDataset({ client, environment, options, logger = new ProgressReporter() }) {
  guardDemoEnvironment(environment);
  if (!process.env.DEVELOPMENT_DEMO_ADMIN_PASSWORD) throw new Error('Set DEVELOPMENT_DEMO_ADMIN_PASSWORD before generating demo users.');
  const rng = new SeededRandom(options.seed);
  if (options.dryRun) return { dryRun: true, config: options.config, seed: options.seed };
  if (options.reset) await resetDemoData(client);
  const dataset = await client.query(
    `INSERT INTO demo_datasets (generator_version, random_seed, size_name, settings)
     VALUES ($1,$2,$3,$4) RETURNING dataset_id`,
    [generatorVersion, options.seed, options.size, JSON.stringify(options.config)],
  );
  const datasetId = dataset.rows[0].dataset_id;
  const context = { client, rng, config: options.config, datasetId, logger, media: options.media, counts: {} };
  try {
    await ensureDemoClinicalPermissions(client);
    await generateClinics(context);
    await generateStaff(context);
    await generateOwners(context);
    await generatePatients(context);
    await generateConsultations(context);
    await generateVaccinations(context);
    await generateLaboratory(context);
    await generateHospitalizations(context);
    await generateSurgeries(context);
    await generateInventory(context);
    await generatePrescriptions(context);
    await generateStockMovements(context);
    await generateSchedules(context);
    await generateInvoicesAndPayments(context);
    if (context.media) await generateMedia(context);
    const validation = await validateDemoDataset(client, datasetId);
    if (!validation.ok) throw new Error(`Demo validation failed: ${validation.failures.map(([name]) => name).join(', ')}`);
    await client.query(`UPDATE demo_datasets SET status = 'Ready', completed_at = now(), record_counts = $2 WHERE dataset_id = $1`, [datasetId, JSON.stringify(validation.counts)]);
    logger.complete();
    return { datasetId, validation, config: options.config, seed: options.seed };
  } catch (error) {
    await client.query(`UPDATE demo_datasets SET status = 'Failed', completed_at = now() WHERE dataset_id = $1`, [datasetId]);
    throw error;
  }
}

export async function resetDemoData(client, datasetId) {
  const filter = datasetId ? ' = $1' : ' IS NOT NULL';
  const values = datasetId ? [datasetId] : [];
  const tables = ['payments','invoices','schedule_entries','prescriptions','stock_movements','inventory_products','surgeries','hospitalizations','laboratory_reports','vaccinations','consultations','patient_weights','media_assets','patients','owners'];
  await client.query('BEGIN');
  try {
    for (const table of tables) await client.query(`DELETE FROM ${table} WHERE demo_dataset_id${filter}`, values);
    await client.query(`DELETE FROM clinic_memberships WHERE user_id IN (SELECT user_id FROM users WHERE is_demo AND demo_dataset_id${filter})`, values);
    await client.query(`DELETE FROM users WHERE is_demo AND demo_dataset_id${filter}`, values);
    await client.query(`DELETE FROM roles WHERE clinic_id IN (SELECT clinic_id FROM clinics WHERE is_demo AND demo_dataset_id${filter})`, values);
    await client.query(`DELETE FROM clinics WHERE is_demo AND demo_dataset_id${filter}`, values);
    if (datasetId) await client.query('DELETE FROM demo_datasets WHERE dataset_id = $1', [datasetId]);
    await client.query('COMMIT');
  } catch (error) { await client.query('ROLLBACK'); throw error; }
}

function guardDemoEnvironment(environment) {
  if (environment.NODE_ENV === 'production' || !environment.demoDataGeneratorEnabled) {
    throw new Error('Demo generation is disabled. Enable it only in development or approved staging.');
  }
}

async function generateClinics(ctx) {
  ctx.logger.phase('clinics', ctx.config.clinics);
  const rows = Array.from({ length: ctx.config.clinics }, (_, index) => [
    `${['North','Central','Lakeside','Green','Sunrise','Heritage','Cedar','Riverside'][index % 8]} ${ctx.rng.pick(['Veterinary Hospital','Animal Care','Vet Centre'])} ${index + 1}`,
    'Active', ctx.rng.pick(['Starter','Professional','Enterprise']), true, ctx.datasetId,
  ]);
  await insertMany(ctx.client, 'clinics', ['name','status','subscription_plan','is_demo','demo_dataset_id'], rows, ctx.config.batchSize);
  ctx.clinics = (await ctx.client.query('SELECT clinic_id, name FROM clinics WHERE demo_dataset_id = $1 ORDER BY name', [ctx.datasetId])).rows;
  ctx.counts.clinics = ctx.clinics.length;
}

async function generateStaff(ctx) {
  ctx.logger.phase('staff', ctx.config.staff);
  const roleRows = ctx.clinics.flatMap((clinic) => roleNames.map((name) => [clinic.clinic_id, name, 'Synthetic demonstration role', false]));
  await insertMany(ctx.client, 'roles', ['clinic_id','name','description','is_system_role'], roleRows, ctx.config.batchSize);
  const roles = (await ctx.client.query('SELECT role_id, clinic_id, name FROM roles WHERE clinic_id = ANY($1::uuid[])', [ctx.clinics.map((c) => c.clinic_id)])).rows;
  const rolesByClinic = Map.groupBy(roles, (role) => role.clinic_id);
  const dummyHash = await hashPassword(randomUUID());
  const demoAdminHash = await hashPassword(process.env.DEVELOPMENT_DEMO_ADMIN_PASSWORD);
  const staffRows = [];
  for (let index = 0; index < ctx.config.staff; index++) {
    const clinic = ctx.clinics[index % ctx.clinics.length];
    const clinicRoles = rolesByClinic.get(clinic.clinic_id);
    const role = clinicRoles[index === 0 ? 0 : ctx.rng.int(clinicRoles.length)];
    const isDemoAdmin = index === 0;
    staffRows.push([clinic.clinic_id, `${ctx.rng.pick(firstNames)} ${ctx.rng.pick(lastNames)}`, isDemoAdmin ? 'demo.admin@avera.test' : `demo.staff.${ctx.datasetId.slice(0, 8)}.${index}@avera.test`, `080${String(10000000 + index).padStart(8, '0')}`, isDemoAdmin ? demoAdminHash : dummyHash, role.name === 'Clinic Administrator' ? 'ClinicAdministrator' : 'ClinicStaff', 'Active', role.role_id, true, ctx.datasetId]);
  }
  await insertMany(ctx.client, 'users', ['clinic_id','full_name','email','phone','password_hash','account_type','status','role_id','is_demo','demo_dataset_id'], staffRows, ctx.config.batchSize);
  ctx.staff = (await ctx.client.query('SELECT user_id, clinic_id, role_id, full_name FROM users WHERE demo_dataset_id = $1', [ctx.datasetId])).rows;
  await insertMany(ctx.client, 'clinic_memberships', ['user_id','clinic_id','role_id','membership_status','activated_at'], ctx.staff.map((user) => [user.user_id, user.clinic_id, user.role_id, 'Active', new Date()]), ctx.config.batchSize);
  await grantDemoRolePermissions(ctx.client, ctx.clinics.map((clinic) => clinic.clinic_id));
  ctx.staffByClinic = Map.groupBy(ctx.staff, (user) => user.clinic_id);
  ctx.counts.staff = ctx.staff.length;
}

const clinicalPermissionDefinitions = [
  ['clinics.view', 'View the active clinic workspace'], ['dashboard.view', 'View clinic dashboard'],
  ['patients.view', 'View patients'], ['patients.create', 'Create patients'], ['patients.edit', 'Edit patients'],
  ['consultations.view', 'View consultations'], ['consultations.create', 'Create consultations'], ['consultations.edit', 'Edit consultations'],
  ['vaccinations.view', 'View vaccinations'], ['vaccinations.add', 'Add vaccinations'],
  ['laboratory.view', 'View laboratory reports'], ['laboratory.add', 'Add laboratory results'],
  ['hospitalization.view', 'View hospitalizations'], ['hospitalization.add', 'Add hospitalizations'],
  ['surgery.view', 'View surgeries'], ['surgery.add', 'Add surgeries'],
  ['prescriptions.view', 'View prescriptions'], ['prescriptions.create', 'Create prescriptions'],
  ['inventory.view', 'View inventory'], ['inventory.manage', 'Manage inventory'],
  ['appointments.view', 'View schedule'], ['appointments.create', 'Create schedule entries'],
  ['billing.view', 'View billing'], ['billing.manage', 'Manage billing'], ['media.view', 'View media'],
  ['users.view', 'View users'], ['users.create', 'Create users'], ['users.assign_roles', 'Assign roles'],
];

async function ensureDemoClinicalPermissions(client) {
  for (const [key, description] of clinicalPermissionDefinitions) {
    await client.query('INSERT INTO permissions (permission_key, description) VALUES ($1,$2) ON CONFLICT (permission_key) DO NOTHING', [key, description]);
  }
}

async function grantDemoRolePermissions(client, clinicIds) {
  await client.query(
    `INSERT INTO role_permissions (role_id, permission_id)
       SELECT r.role_id, p.permission_id
         FROM roles r CROSS JOIN permissions p
        WHERE r.clinic_id = ANY($1::uuid[]) AND p.permission_key = ANY($2::text[])
       ON CONFLICT DO NOTHING`,
    [clinicIds, clinicalPermissionDefinitions.map(([key]) => key)],
  );
}

async function generateOwners(ctx) {
  ctx.logger.phase('owners', ctx.config.owners);
  const start = yearsAgo(ctx.config.years); const now = new Date();
  const rows = Array.from({ length: ctx.config.owners }, (_, index) => {
    const clinic = ctx.clinics[index % ctx.clinics.length];
    return [clinic.clinic_id, `${ctx.rng.pick(firstNames)} ${ctx.rng.pick(lastNames)}`, `080${String(20000000 + index).padStart(8, '0')}`, `owner.${ctx.datasetId.slice(0, 6)}.${index}@example.test`, `${10 + (index % 90)} Wellness Road`, 'Lagos', 'Lagos', ctx.rng.pick(['Phone','SMS','Email']), `080${String(30000000 + index).padStart(8, '0')}`, true, ctx.rng.date(start, now), true, ctx.datasetId];
  });
  await insertMany(ctx.client, 'owners', ['clinic_id','full_name','phone','email','address','city','state','preferred_contact_method','emergency_contact','communication_consent','registered_at','is_demo','demo_dataset_id'], rows, ctx.config.batchSize);
  ctx.owners = (await ctx.client.query('SELECT owner_id, clinic_id, registered_at FROM owners WHERE demo_dataset_id = $1', [ctx.datasetId])).rows;
  ctx.ownersByClinic = Map.groupBy(ctx.owners, (owner) => owner.clinic_id); ctx.counts.owners = ctx.owners.length;
}

async function generatePatients(ctx) {
  ctx.logger.phase('patients', ctx.config.patients); const now = new Date(); const start = yearsAgo(ctx.config.years);
  const rows = []; const weights = [];
  for (let index = 0; index < ctx.config.patients; index++) {
    const clinic = ctx.clinics[index % ctx.clinics.length]; const owner = ctx.rng.pick(ctx.ownersByClinic.get(clinic.clinic_id));
    const speciesChoice = weightedSpecies(ctx.rng); const ageYears = ctx.rng.range(.2, 14); const dob = new Date(now.getTime() - ageYears * 365.25 * 86400000);
    const registered = ctx.rng.date(new Date(Math.max(dob.getTime(), start.getTime())), now); const deceased = ctx.rng.chance(.035) ? ctx.rng.date(registered, now) : null; const status = deceased ? 'Deceased' : ctx.rng.chance(.03) ? 'Relocated' : 'Active';
    rows.push([clinic.clinic_id, owner.owner_id, `DEM-${String(index + 1).padStart(7, '0')}`, `${ctx.rng.pick(['Bella','Max','Luna','Charlie','Coco','Daisy','Rocky','Milo'])} ${index + 1}`, speciesChoice[0], ctx.rng.pick(speciesChoice[2]), ctx.rng.pick(['Female','Male']), ctx.rng.pick(['Intact','Neutered','Spayed']), dob, ctx.rng.pick(['Black','Brown','White','Grey','Tan']), Number(ctx.rng.range(.8, speciesChoice[0] === 'Cattle' ? 500 : 45).toFixed(2)), ctx.rng.chance(.45) ? `MC-${ctx.datasetId.slice(0, 5)}-${index}` : null, status, ctx.rng.chance(.05) ? 'Synthetic allergy alert' : null, ctx.rng.chance(.04) ? 'Synthetic clinical alert' : null, 'Uninsured', ctx.rng.pick(ctx.staffByClinic.get(clinic.clinic_id)).user_id, registered, deceased, `avatar:${speciesChoice[0].toLowerCase()}`, true, ctx.datasetId]);
  }
  await insertMany(ctx.client, 'patients', ['clinic_id','owner_id','hospital_number','name','species','breed','sex','reproductive_status','date_of_birth','colour','current_weight_kg','microchip_number','status','allergies','alerts','insurance_status','primary_veterinarian_id','registered_at','deceased_at','image_placeholder','is_demo','demo_dataset_id'], rows, ctx.config.batchSize);
  ctx.patients = (await ctx.client.query('SELECT patient_id, clinic_id, owner_id, species, date_of_birth, registered_at, deceased_at, current_weight_kg FROM patients WHERE demo_dataset_id = $1', [ctx.datasetId])).rows;
  ctx.patientsByClinic = Map.groupBy(ctx.patients, (patient) => patient.clinic_id);
  ctx.patientsById = new Map(ctx.patients.map((patient) => [patient.patient_id, patient]));
  weights.push(...ctx.patients.map((patient) => [patient.clinic_id, patient.patient_id, patient.registered_at, patient.current_weight_kg, 'Registration', true, ctx.datasetId]));
  await insertMany(ctx.client, 'patient_weights', ['clinic_id','patient_id','measured_at','weight_kg','source','is_demo','demo_dataset_id'], weights, ctx.config.batchSize); ctx.counts.patients = ctx.patients.length;
}

async function generateConsultations(ctx) {
  ctx.logger.phase('consultations', ctx.config.consultations); const rows = [];
  for (let index = 0; index < ctx.config.consultations; index++) {
    const clinic = ctx.clinics[index % ctx.clinics.length]; const patient = ctx.rng.pick(ctx.patientsByClinic.get(clinic.clinic_id)); const occurred = validClinicalDate(ctx.rng, patient); const diagnosis = diagnosisFor(ctx.rng, patient.species, occurred);
    rows.push([clinic.clinic_id, patient.patient_id, ctx.rng.pick(ctx.staffByClinic.get(clinic.clinic_id)).user_id, occurred, diagnosis, 'Synthetic history; not for clinical use.', 'Synthetic examination findings.', patient.current_weight_kg, Number(ctx.rng.range(37.5, 40).toFixed(1)), Math.round(ctx.rng.range(70, 130)), Math.round(ctx.rng.range(16, 35)), diagnosis, `Differentials for ${diagnosis}`, diagnosis, 'Synthetic treatment plan.', ctx.rng.chance(.35) ? plusDays(occurred, ctx.rng.int(30) + 3) : null, 'Completed', Number(ctx.rng.range(5000, 45000).toFixed(2)), true, ctx.datasetId]);
  }
  await insertMany(ctx.client, 'consultations', ['clinic_id','patient_id','clinician_id','occurred_at','chief_complaint','history','examination','weight_kg','temperature_c','pulse','respiration','assessment','differential_diagnoses','final_diagnosis','treatment','follow_up_at','status','charge','is_demo','demo_dataset_id'], rows, ctx.config.batchSize);
  ctx.consultations = (await ctx.client.query('SELECT consultation_id, clinic_id, patient_id, occurred_at, final_diagnosis, charge FROM consultations WHERE demo_dataset_id = $1', [ctx.datasetId])).rows; ctx.consultationsByClinic = Map.groupBy(ctx.consultations, (item) => item.clinic_id); ctx.consultationsByPatient = Map.groupBy(ctx.consultations, (item) => item.patient_id); ctx.counts.consultations = ctx.consultations.length;
}

async function generateVaccinations(ctx) { await generateLinked(ctx, 'vaccinations', ctx.config.vaccinations, (clinic, patient, consult) => [clinic.clinic_id, patient.patient_id, consult.consultation_id, ctx.rng.pick(vaccineBySpecies[patient.species]), 'SyntheticVet', `VAC-${ctx.rng.int(999999)}`, plusDays(consult.occurred_at, 365), 'Subcutaneous', '1 ml', 'Left shoulder', consult.occurred_at, plusDays(consult.occurred_at, 365), ctx.rng.pick(ctx.staffByClinic.get(clinic.clinic_id)).user_id, `CERT-${ctx.rng.int(999999)}`, 'Synthetic vaccination record.', 'Pending', 'Completed', true, ctx.datasetId], ['clinic_id','patient_id','consultation_id','vaccine_name','manufacturer','batch_number','expiry_date','route','dose','injection_site','administered_at','next_due_at','administered_by','certificate_number','notes','reminder_status','status','is_demo','demo_dataset_id']); }
async function generateLaboratory(ctx) { await generateLinked(ctx, 'laboratory_reports', ctx.config.laboratoryReports, (clinic, patient, consult) => [clinic.clinic_id, patient.patient_id, consult.consultation_id, consult.occurred_at, plusDays(consult.occurred_at, 1), ctx.rng.pick(['PCV','CBC','Blood smear','Serum biochemistry','Faecal flotation','Urinalysis','Skin scraping','Rapid diagnostic test']), 'Reviewed', labSummary(consult.final_diagnosis), JSON.stringify({ synthetic: true, flag: consult.final_diagnosis.includes('Ehrlichiosis') ? 'Low platelets' : 'Within expected synthetic range' }), ctx.rng.pick(ctx.staffByClinic.get(clinic.clinic_id)).user_id, ctx.rng.pick(ctx.staffByClinic.get(clinic.clinic_id)).user_id, Number(ctx.rng.range(3000, 18000).toFixed(2)), true, ctx.datasetId], ['clinic_id','patient_id','consultation_id','requested_at','reported_at','test_type','status','result_summary','result_values','requested_by','reviewed_by','cost','is_demo','demo_dataset_id']); }
async function generateHospitalizations(ctx) { await generateLinked(ctx, 'hospitalizations', ctx.config.hospitalizations, (clinic, patient, consult) => { const days = ctx.rng.pick([1,3,5,7]); return [clinic.clinic_id, patient.patient_id, consult.consultation_id, consult.occurred_at, ctx.rng.chance(.15) ? null : plusDays(consult.occurred_at, days), ctx.rng.pick(['General','Infectious Disease','Large Animal']), `C-${ctx.rng.int(99) + 1}`, ctx.rng.pick(ctx.staffByClinic.get(clinic.clinic_id)).user_id, consult.final_diagnosis, consult.final_diagnosis, JSON.stringify({ durationDays: days, synthetic: true, fluids: 'As indicated' }), ctx.rng.pick(['Discharged','Recovering','Transferred','Deceased']), Number(ctx.rng.range(15000, 250000).toFixed(2)), true, ctx.datasetId]; }, ['clinic_id','patient_id','consultation_id','admitted_at','discharged_at','ward','cage_or_pen','attending_veterinarian_id','reason','diagnosis','treatment_plan','outcome','cost','is_demo','demo_dataset_id']); }
async function generateSurgeries(ctx) { await generateLinked(ctx, 'surgeries', ctx.config.surgeries, (clinic, patient, consult) => [clinic.clinic_id, patient.patient_id, consult.consultation_id, consult.occurred_at, ctx.rng.pick(['Spay','Neuter','Caesarean section','Wound repair','Tumour excision','Hernia repair','Dental extraction','Debridement']), ctx.rng.pick(ctx.staffByClinic.get(clinic.clinic_id)).user_id, 'Synthetic balanced anaesthesia protocol', ctx.rng.chance(.1) ? 'Minor synthetic complication' : null, 'Synthetic recovery note', plusDays(consult.occurred_at, 14), Number(ctx.rng.range(30000, 400000).toFixed(2)), true, ctx.datasetId], ['clinic_id','patient_id','consultation_id','performed_at','procedure_name','surgeon_id','anaesthesia_protocol','complication_notes','recovery_notes','follow_up_at','cost','is_demo','demo_dataset_id']); }

async function generateInventory(ctx) { ctx.logger.phase('inventory products', ctx.config.inventoryProducts); const rows = Array.from({ length: ctx.config.inventoryProducts }, (_, index) => { const clinic = ctx.clinics[index % ctx.clinics.length]; const name = products[index % products.length]; const quantity = ctx.rng.int(120); return [clinic.clinic_id, `${name} ${index + 1}`, name, ctx.rng.pick(['Antibiotics','Antiparasitics','Vaccines','NSAIDs','Anaesthetics','Fluids','Consumables','Laboratory materials']), 'SyntheticVet', 'Synthetic Supplier', `B-${ctx.rng.int(999999)}`, ctx.rng.date(new Date(), plusDays(new Date(), 730)), Number(ctx.rng.range(500, 10000).toFixed(2)), Number(ctx.rng.range(1500, 25000).toFixed(2)), quantity, 10, 'Room temperature', false, quantity === 0 ? 'OutOfStock' : 'Active', true, ctx.datasetId]; }); await insertMany(ctx.client, 'inventory_products', ['clinic_id','name','generic_name','category','manufacturer','supplier','batch_number','expiry_date','purchase_price','selling_price','quantity','reorder_level','storage_conditions','controlled','status','is_demo','demo_dataset_id'], rows, ctx.config.batchSize); ctx.products = (await ctx.client.query('SELECT inventory_product_id, clinic_id, name FROM inventory_products WHERE demo_dataset_id = $1',[ctx.datasetId])).rows; ctx.productsByClinic = Map.groupBy(ctx.products,(item)=>item.clinic_id); ctx.counts.inventoryProducts = ctx.products.length; }
async function generatePrescriptions(ctx) { await generateLinked(ctx, 'prescriptions', ctx.config.prescriptions, (clinic, patient, consult) => { const product = ctx.rng.pick(ctx.productsByClinic.get(clinic.clinic_id)); return [clinic.clinic_id,patient.patient_id,consult.consultation_id,product.inventory_product_id,consult.occurred_at,product.name,'10 mg/ml','Synthetic dose','Oral','Twice daily',ctx.rng.pick([3,5,7,14]),ctx.rng.int(10)+1,'Synthetic content only; not a prescription.',ctx.rng.pick(ctx.staffByClinic.get(clinic.clinic_id)).user_id,'None',true,ctx.datasetId]; }, ['clinic_id','patient_id','consultation_id','inventory_product_id','prescribed_at','drug_name','concentration','dose','route','frequency','duration_days','quantity','instructions','prescriber_id','refill_status','is_demo','demo_dataset_id']); }
async function generateStockMovements(ctx) { ctx.logger.phase('stock movements', ctx.config.inventoryMovements); const rows = Array.from({length:ctx.config.inventoryMovements},(_,index)=>{const clinic=ctx.clinics[index%ctx.clinics.length];const product=ctx.rng.pick(ctx.productsByClinic.get(clinic.clinic_id));const consult=ctx.rng.pick(ctx.consultationsByClinic.get(clinic.clinic_id));const delta=ctx.rng.chance(.72)?-(ctx.rng.int(3)+1):(ctx.rng.int(30)+5);return [clinic.clinic_id,product.inventory_product_id,consult.consultation_id,consult.occurred_at,delta<0?'Dispensed':'Purchase',delta,`SYN-${index}`,true,ctx.datasetId];});await insertMany(ctx.client,'stock_movements',['clinic_id','inventory_product_id','consultation_id','occurred_at','movement_type','quantity_delta','reference','is_demo','demo_dataset_id'],rows,ctx.config.batchSize);ctx.counts.stockMovements=rows.length; }
async function generateSchedules(ctx) { ctx.logger.phase('schedule',ctx.config.schedules);const rows=Array.from({length:ctx.config.schedules},(_,index)=>{const clinic=ctx.clinics[index%ctx.clinics.length];const patient=ctx.rng.pick(ctx.patientsByClinic.get(clinic.clinic_id));const owner=ctx.ownersByClinic.get(clinic.clinic_id).find((item)=>item.owner_id===patient.owner_id);const scheduled=ctx.rng.date(yearsAgo(ctx.config.years),plusDays(new Date(),60));return [clinic.clinic_id,patient.patient_id,owner.owner_id,ctx.rng.pick(ctx.staffByClinic.get(clinic.clinic_id)).user_id,scheduled,ctx.rng.pick(['Wellness','Vaccination','Recheck','Laboratory','Farm visit','Emergency']),scheduled>new Date()?'Scheduled':ctx.rng.pick(['Completed','Cancelled','Missed']),'Synthetic schedule entry',true,ctx.datasetId];});await insertMany(ctx.client,'schedule_entries',['clinic_id','patient_id','owner_id','assigned_staff_id','scheduled_at','visit_type','status','notes','is_demo','demo_dataset_id'],rows,ctx.config.batchSize);ctx.counts.schedules=rows.length; }
async function generateInvoicesAndPayments(ctx) { ctx.logger.phase('invoices',ctx.config.invoices);const rows=[];for(let index=0;index<ctx.config.invoices;index++){const clinic=ctx.clinics[index%ctx.clinics.length];const consult=ctx.rng.pick(ctx.consultationsByClinic.get(clinic.clinic_id));const patient=ctx.patientsById.get(consult.patient_id);const total=Number((Number(consult.charge)+ctx.rng.range(1000,30000)).toFixed(2));const paid=index<ctx.config.payments?(ctx.rng.chance(.7)?total:Number((total*.5).toFixed(2))):0;rows.push([clinic.clinic_id,patient.owner_id,patient.patient_id,consult.consultation_id,`INV-${clinic.clinic_id.slice(0,4)}-${String(index+1).padStart(7,'0')}`,paid===total?'Paid':paid>0?'Partially Paid':ctx.rng.chance(.2)?'Overdue':'Issued',total,0,0,total,paid,Number((total-paid).toFixed(2)),consult.occurred_at,plusDays(consult.occurred_at,14),true,ctx.datasetId]);}await insertMany(ctx.client,'invoices',['clinic_id','owner_id','patient_id','consultation_id','invoice_number','status','subtotal','tax','discount','total','amount_paid','balance','issued_at','due_at','is_demo','demo_dataset_id'],rows,ctx.config.batchSize);const invoices=(await ctx.client.query('SELECT invoice_id,clinic_id,amount_paid,issued_at FROM invoices WHERE demo_dataset_id=$1',[ctx.datasetId])).rows;const payments=invoices.filter((invoice)=>Number(invoice.amount_paid)>0).map((invoice)=>[invoice.clinic_id,invoice.invoice_id,invoice.issued_at,invoice.amount_paid,ctx.rng.pick(['Cash','Card','Bank transfer','Mobile transfer','Insurance']),true,ctx.datasetId]);await insertMany(ctx.client,'payments',['clinic_id','invoice_id','paid_at','amount','method','is_demo','demo_dataset_id'],payments,ctx.config.batchSize);ctx.counts.invoices=rows.length;ctx.counts.payments=payments.length; }
async function generateMedia(ctx) { ctx.logger.phase('media metadata',ctx.config.mediaAssets);const rows=Array.from({length:ctx.config.mediaAssets},(_,index)=>{const patient=ctx.patients[index%ctx.patients.length];return [patient.clinic_id,patient.patient_id,ctx.rng.pick(['Patient photo','Radiograph','Laboratory image','Report thumbnail']),'image/png',ctx.rng.int(90000)+10000,`synthetic:${patient.species.toLowerCase()}:${index}`,new Date(),true,ctx.datasetId];});await insertMany(ctx.client,'media_assets',['clinic_id','patient_id','category','file_type','file_size_bytes','placeholder_key','created_at','is_demo','demo_dataset_id'],rows,ctx.config.batchSize);ctx.counts.mediaAssets=rows.length;}
async function generateLinked(ctx, table, count, factory, columns) { ctx.logger.phase(table,count);const rows=[];for(let index=0;index<count;index++){const clinic=ctx.clinics[index%ctx.clinics.length];let patient=ctx.rng.pick(ctx.patientsByClinic.get(clinic.clinic_id));let consult=ctx.rng.pick(ctx.consultationsByPatient.get(patient.patient_id) ?? []);if(!consult){consult=ctx.rng.pick(ctx.consultationsByClinic.get(clinic.clinic_id));patient=ctx.patientsById.get(consult.patient_id);}rows.push(factory(clinic,patient,consult));}await insertMany(ctx.client,table,columns,rows,ctx.config.batchSize);ctx.counts[table]=rows.length;}

async function insertMany(client, table, columns, rows, batchSize) { for(let offset=0;offset<rows.length;offset+=batchSize){const batch=rows.slice(offset,offset+batchSize);const values=[];const placeholders=batch.map((row,rowIndex)=>`(${row.map((_,columnIndex)=>`$${rowIndex*columns.length+columnIndex+1}`).join(',')})`).join(',');for(const row of batch)values.push(...row);await client.query(`INSERT INTO ${table} (${columns.join(',')}) VALUES ${placeholders}`,values);} }
function weightedSpecies(rng){const point=rng.next();let total=0;for(const candidate of species){total+=candidate[1];if(point<=total)return candidate;}return species[0];}
function diagnosisFor(rng, speciesName, occurred){const wet=[4,5,6,7,8,9].includes(occurred.getUTCMonth()+1);const candidates=['Dog','Cat','Rabbit','Bird','Exotic'].includes(speciesName)?smallAnimalDiagnoses:farmDiagnoses;return wet&&rng.chance(.35)?rng.pick(['Ehrlichiosis','Babesiosis','Tick infestation','Respiratory disease']):rng.pick(candidates);}
function labSummary(diagnosis){if(['Ehrlichiosis','Babesiosis'].includes(diagnosis))return 'Synthetic anaemia and thrombocytopenia pattern.';if(diagnosis==='Helminthiasis')return 'Synthetic positive flotation pattern.';return 'Synthetic result consistent with recorded assessment.';}
function validClinicalDate(rng,patient){const start=new Date(patient.registered_at);const end=patient.deceased_at?new Date(patient.deceased_at):new Date();return rng.date(start,end);}
function yearsAgo(years){const value=new Date();value.setUTCFullYear(value.getUTCFullYear()-years);return value;}
function plusDays(value,days){return new Date(new Date(value).getTime()+days*86400000);}
