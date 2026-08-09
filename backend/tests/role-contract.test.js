import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { changeClinicUserRole } from '../src/routes/clinic-routes.js';
import { defaultClinicRoleTemplates, ensureDefaultClinicRoles } from '../src/security/default-clinic-roles.js';
import { publicUser } from '../src/services/auth-service.js';

const roleUuid = '9c169399-c6d6-437c-8c55-74b0521d7600';
const veterinarianUuid = '1a169399-c6d6-437c-8c55-74b0521d7600';

test('public auth user separates a readable role from its identifier', () => {
  const value = publicUser(
    { user_id: 'user-1', clinic_id: 'clinic-1', full_name: 'Clinic Admin', email: 'admin@example.test', account_type: 'ClinicAdministrator', status: 'Active', role_id: roleUuid },
    ['staff.roles.manage'],
    {},
    { role_id: roleUuid, code: 'clinic_administrator', name: 'Clinic Administrator' },
  );
  assert.equal(value.roleId, roleUuid);
  assert.equal(value.roleCode, 'clinic_administrator');
  assert.equal(value.roleName, 'Clinic Administrator');
  assert.deepEqual(value.role, { id: roleUuid, code: 'clinic_administrator', name: 'Clinic Administrator' });
  assert.notEqual(value.roleName, value.roleId);
});

test('role migration is idempotent, clinic-scoped, and grants only clinic administrators', () => {
  const migration = fs.readFileSync(new URL('../migrations/014_role_contract_and_administrator_protection.sql', import.meta.url), 'utf8');
  assert.match(migration, /ADD COLUMN IF NOT EXISTS code/);
  assert.match(migration, /roles_clinic_code_unique/);
  assert.match(migration, /row_number\(\) OVER/);
  assert.match(migration, /duplicate_number > 1/);
  assert.match(migration, /staff\.roles\.manage/);
  assert.match(migration, /r\.code = 'clinic_administrator'/);
  assert.match(migration, /r\.clinic_id IS NOT NULL/);
  assert.match(migration, /ON CONFLICT DO NOTHING/);
});

test('standard clinic roles are tenant-scoped, assignable, and receive permission mappings', async () => {
  const calls = [];
  let roleIndex = 0;
  const client = {
    async query(sql, parameters = []) {
      calls.push({ sql, parameters });
      if (sql.includes('SELECT role_id') && sql.includes('FROM roles')) {
        return { rows: [] };
      }
      if (sql.includes('INSERT INTO roles')) {
        roleIndex += 1;
        return { rows: [{ role_id: `role-${roleIndex}` }] };
      }
      if (sql.includes('SELECT permission_id, permission_key')) {
        return {
          rows: parameters[0].map((key, index) => ({
            permission_id: `permission-${index}`,
            permission_key: key,
          })),
        };
      }
      return { rows: [] };
    },
  };

  await ensureDefaultClinicRoles(client, {
    clinicId: 'clinic-1',
    actorUserId: 'admin-1',
  });

  assert.equal(defaultClinicRoleTemplates.length, 9);
  assert.equal(new Set(defaultClinicRoleTemplates.map((role) => role.code)).size, 9);
  assert.equal(defaultClinicRoleTemplates.some((role) => role.code === 'clinic_administrator'), false);
  assert.ok(defaultClinicRoleTemplates.some((role) => role.code === 'veterinarian'));
  assert.ok(defaultClinicRoleTemplates.some((role) => role.code === 'pharmacist'));
  assert.ok(defaultClinicRoleTemplates.some((role) => role.code === 'sales_representative'));
  assert.equal(calls.filter(({ sql }) => sql.includes('INSERT INTO roles')).length, 9);
  assert.equal(calls.filter(({ sql }) => sql.includes('INSERT INTO role_permissions')).length, 9);
  for (const call of calls.filter(({ sql }) => sql.includes('INSERT INTO roles'))) {
    assert.equal(call.parameters[0], 'clinic-1');
    assert.equal(call.parameters[4], 'admin-1');
    assert.match(call.sql, /ON CONFLICT \(clinic_id, name\) DO UPDATE/);
  }
});

test('existing clinic role repair is idempotent and preserves canonical role IDs', async () => {
  const roles = new Map();
  const calls = [];
  const client = {
    async query(sql, parameters = []) {
      calls.push({ sql, parameters });
      if (sql.includes('SELECT role_id') && sql.includes('FROM roles')) {
        const existing = roles.get(parameters[1]);
        return { rows: existing ? [{ role_id: existing }] : [] };
      }
      if (sql.includes('INSERT INTO roles')) {
        const roleId = `stable-${parameters[1]}`;
        roles.set(parameters[1], roleId);
        return { rows: [{ role_id: roleId }] };
      }
      if (sql.includes('SELECT permission_id, permission_key')) {
        return {
          rows: parameters[0].map((key, index) => ({
            permission_id: `permission-${index}`,
            permission_key: key,
          })),
        };
      }
      return { rows: [] };
    },
  };

  await ensureDefaultClinicRoles(client, {
    clinicId: 'clinic-1',
    actorUserId: 'admin-1',
  });
  const firstIds = new Map(roles);
  await ensureDefaultClinicRoles(client, {
    clinicId: 'clinic-1',
    actorUserId: 'admin-1',
  });

  assert.deepEqual(roles, firstIds);
  assert.equal(calls.filter(({ sql }) => sql.includes('INSERT INTO roles')).length, 9);
  assert.equal(calls.filter(({ sql }) => sql.includes('INSERT INTO role_permissions')).length, 18);
  for (const call of calls.filter(({ sql }) => sql.includes('INSERT INTO role_permissions'))) {
    assert.match(call.sql, /ON CONFLICT DO NOTHING/);
  }
});

test('clinic role change updates identity and membership and writes a structured audit event', async () => {
  const calls = [];
  const client = {
    async query(sql, parameters = []) {
      calls.push({ sql, parameters });
      if (sql.includes('SELECT r.code AS role_code')) {
        assert.deepEqual(parameters, ['admin-user', 'clinic-1']);
        return { rows: [{ role_code: 'clinic_administrator' }] };
      }
      if (sql.includes('FOR UPDATE OF u')) {
        return { rows: [{ user_id: 'target-user', role_id: roleUuid, role_code: 'receptionist', role_name: 'Receptionist' }] };
      }
      if (sql.includes('FROM roles') && sql.includes('role_id = $1')) {
        assert.deepEqual(parameters, [veterinarianUuid, 'clinic-1']);
        return { rows: [{ role_id: veterinarianUuid, code: 'veterinarian', name: 'Veterinarian' }] };
      }
      return { rows: [] };
    },
  };

  const result = await changeClinicUserRole(client, {
    clinicId: 'clinic-1',
    actorUserId: 'admin-user',
    targetUserId: 'target-user',
    roleId: veterinarianUuid,
    sessionId: 'session-1',
    ipAddress: '127.0.0.1',
  });

  assert.equal(result.roleName, 'Veterinarian');
  assert.equal(result.roleId, veterinarianUuid);
  assert.equal(result.accountType, 'ClinicStaff');
  assert.ok(calls.some(({ sql }) => sql.includes('UPDATE users')));
  assert.ok(calls.some(({ sql }) => sql.includes('UPDATE clinic_memberships')));
  const audit = calls.find(({ sql }) => sql.includes('INSERT INTO audit_logs'));
  assert.ok(audit);
  assert.equal(audit.parameters[4], 'staff.role_changed');
  assert.deepEqual(audit.parameters[5], { roleId: roleUuid, roleCode: 'receptionist', roleName: 'Receptionist' });
  assert.deepEqual(audit.parameters[6], { roleId: veterinarianUuid, roleCode: 'veterinarian', roleName: 'Veterinarian' });
});

test('a role from another clinic is rejected before any mutation', async () => {
  const calls = [];
  const client = {
    async query(sql) {
      calls.push(sql);
      if (sql.includes('SELECT r.code AS role_code')) return { rows: [{ role_code: 'clinic_administrator' }] };
      if (sql.includes('FOR UPDATE OF u')) return { rows: [{ user_id: 'target-user', role_id: roleUuid, role_code: 'receptionist' }] };
      if (sql.includes('FROM roles')) return { rows: [] };
      return { rows: [] };
    },
  };
  await assert.rejects(
    changeClinicUserRole(client, { clinicId: 'clinic-1', actorUserId: 'admin-user', targetUserId: 'target-user', roleId: veterinarianUuid }),
    (error) => error.code === 'invalid_clinic_role' && error.statusCode === 400,
  );
  assert.equal(calls.some((sql) => sql.includes('UPDATE users')), false);
});

test('the final active clinic administrator cannot be demoted', async () => {
  const calls = [];
  const client = {
    async query(sql) {
      calls.push(sql);
      if (sql.includes('SELECT r.code AS role_code')) return { rows: [{ role_code: 'clinic_administrator' }] };
      if (sql.includes('FOR UPDATE OF u')) return { rows: [{ user_id: 'target-user', role_id: roleUuid, role_code: 'clinic_administrator', role_name: 'Clinic Administrator' }] };
      if (sql.includes('FROM roles')) return { rows: [{ role_id: veterinarianUuid, code: 'veterinarian', name: 'Veterinarian' }] };
      if (sql.includes('count(*)::int')) return { rows: [{ count: 1 }] };
      return { rows: [] };
    },
  };
  await assert.rejects(
    changeClinicUserRole(client, { clinicId: 'clinic-1', actorUserId: 'admin-user', targetUserId: 'target-user', roleId: veterinarianUuid }),
    (error) => error.code === 'final_clinic_administrator' && error.statusCode === 409,
  );
  assert.equal(calls.some((sql) => sql.includes('UPDATE users')), false);
});

test('ordinary or inactive staff cannot mutate clinic roles directly', async () => {
  const calls = [];
  const client = {
    async query(sql) {
      calls.push(sql);
      if (sql.includes('SELECT r.code AS role_code')) {
        return { rows: [{ role_code: 'veterinarian' }] };
      }
      return { rows: [] };
    },
  };

  await assert.rejects(
    changeClinicUserRole(client, {
      clinicId: 'clinic-1',
      actorUserId: 'vet-user',
      targetUserId: 'target-user',
      roleId: veterinarianUuid,
    }),
    (error) => error.code === 'role_management_forbidden' && error.statusCode === 403,
  );
  assert.equal(calls.some((sql) => sql.includes('UPDATE users')), false);
});

test('route guards require explicit permission, Clinic Administrator scope, and block self changes', () => {
  const source = fs.readFileSync(new URL('../src/routes/clinic-routes.js', import.meta.url), 'utf8');
  assert.match(source, /requirePermission\(permissions\.staffRolesManage\)/);
  assert.match(source, /accountType !== 'ClinicAdministrator'/);
  assert.match(source, /request\.params\.userId === request\.auth\.userId/);
  assert.match(source, /u\.clinic_id = \$1/);
  assert.match(source, /ensureDefaultClinicRoles/);
  assert.match(source, /code <> 'clinic_administrator'/);
});
