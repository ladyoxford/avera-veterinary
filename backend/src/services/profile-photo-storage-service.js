const supportedTypes = new Set(['image/jpeg', 'image/png']);

export class ProfilePhotoStorageService {
  constructor({ environment, fetchImpl = fetch }) {
    this.environment = environment;
    this.fetch = fetchImpl;
  }

  get configured() {
    return Boolean(
      this.environment.SUPABASE_URL &&
        this.environment.SUPABASE_SERVICE_ROLE_KEY &&
        this.environment.PROFILE_PHOTO_BUCKET,
    );
  }

  validate({ contentType, bytes }) {
    if (!supportedTypes.has(contentType)) {
      throw storageError(400, 'unsupported_profile_photo', 'Choose a JPEG or PNG image.');
    }
    if (!bytes.length || bytes.length > 1024 * 1024) {
      throw storageError(400, 'profile_photo_too_large', 'Choose a profile photo smaller than 1 MB.');
    }
    const jpeg = bytes[0] === 0xff && bytes[1] === 0xd8;
    const png = bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
    if ((contentType === 'image/jpeg' && !jpeg) || (contentType === 'image/png' && !png)) {
      throw storageError(400, 'invalid_profile_photo', 'The selected image could not be read.');
    }
  }

  objectPath({ clinicId, userId, contentType }) {
    const scope = clinicId ?? 'platform';
    const extension = contentType === 'image/png' ? 'png' : 'jpg';
    return `${scope}/${userId}/avatar.${extension}`;
  }

  brandObjectPath({ clinicId, kind, contentType }) {
    const extension = contentType === 'image/png' ? 'png' : 'jpg';
    return `${clinicId}/branding/${kind}.${extension}`;
  }

  patientObjectPath({ clinicId, patientId, contentType }) {
    const extension = contentType === 'image/png' ? 'png' : 'jpg';
    return `${clinicId}/patients/${patientId}/avatar.${extension}`;
  }

  async upload({ clinicId, userId, contentType, bytes }) {
    if (!this.configured) {
      throw storageError(503, 'profile_photo_storage_unavailable', 'Profile photo storage is not configured yet.');
    }
    this.validate({ contentType, bytes });
    const path = this.objectPath({ clinicId, userId, contentType });
    const response = await this.fetch(this.#objectUrl(path), {
      method: 'POST',
      headers: { ...this.#headers(), 'Content-Type': contentType, 'x-upsert': 'true' },
      body: bytes,
    });
    if (!response.ok) {
      throw storageError(502, 'profile_photo_upload_failed', 'The profile photo could not be uploaded. Please try again.');
    }
    return path;
  }

  async uploadBrandAsset({ clinicId, kind, contentType, bytes }) {
    if (!this.configured) {
      throw storageError(503, 'clinic_branding_storage_unavailable', 'Clinic branding storage is not configured yet.');
    }
    this.validate({ contentType, bytes });
    const path = this.brandObjectPath({ clinicId, kind, contentType });
    const response = await this.fetch(this.#objectUrl(path), {
      method: 'POST',
      headers: { ...this.#headers(), 'Content-Type': contentType, 'x-upsert': 'true' },
      body: bytes,
    });
    if (!response.ok) {
      throw storageError(502, 'clinic_branding_upload_failed', 'The clinic image could not be uploaded. Please try again.');
    }
    return path;
  }

  async uploadPatientPhoto({ clinicId, patientId, contentType, bytes }) {
    if (!this.configured) {
      throw storageError(503, 'patient_photo_storage_unavailable', 'Patient photo storage is not configured yet.');
    }
    this.validate({ contentType, bytes });
    const path = this.patientObjectPath({ clinicId, patientId, contentType });
    const response = await this.fetch(this.#objectUrl(path), {
      method: 'POST',
      headers: { ...this.#headers(), 'Content-Type': contentType, 'x-upsert': 'true' },
      body: bytes,
    });
    if (!response.ok) {
      throw storageError(502, 'patient_photo_upload_failed', 'The patient photo could not be uploaded. Please try again.');
    }
    return path;
  }

  async signedUrl(path) {
    if (!path || !this.configured) return null;
    const encoded = path.split('/').map(encodeURIComponent).join('/');
    const response = await this.fetch(`${this.environment.SUPABASE_URL}/storage/v1/object/sign/${encodeURIComponent(this.environment.PROFILE_PHOTO_BUCKET)}/${encoded}`, {
      method: 'POST',
      headers: { ...this.#headers(), 'Content-Type': 'application/json' },
      body: JSON.stringify({ expiresIn: 3600 }),
    });
    if (!response.ok) return null;
    const value = await response.json();
    const signed = value.signedURL ?? value.signedUrl;
    if (!signed) return null;
    return signed.startsWith('http') ? signed : `${this.environment.SUPABASE_URL}/storage/v1${signed}`;
  }

  async remove(path) {
    if (!path || !this.configured) return;
    await this.fetch(this.#objectUrl(path), { method: 'DELETE', headers: this.#headers() });
  }

  #objectUrl(path) {
    const encoded = path.split('/').map(encodeURIComponent).join('/');
    return `${this.environment.SUPABASE_URL}/storage/v1/object/${encodeURIComponent(this.environment.PROFILE_PHOTO_BUCKET)}/${encoded}`;
  }

  #headers() {
    return {
      apikey: this.environment.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${this.environment.SUPABASE_SERVICE_ROLE_KEY}`,
    };
  }
}

function storageError(statusCode, code, message) {
  return Object.assign(new Error(message), { statusCode, code });
}
