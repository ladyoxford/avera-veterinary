import { SubscriptionPaymentGateway } from './subscription-payment-gateway.js';

export class PaystackSubscriptionGateway extends SubscriptionPaymentGateway {
  constructor({ secretKey, publicKey, mode, fetchImpl = globalThis.fetch }) {
    super();
    this.secretKey = secretKey;
    this.publicKey = publicKey;
    this.mode = mode;
    this.fetchImpl = fetchImpl;
  }

  get configured() {
    return this.configurationError == null;
  }

  get configurationError() {
    if (this.mode !== 'test' && this.mode !== 'live') {
      return 'payment_mode_not_configured';
    }
    if (!this.secretKey) return 'gateway_not_configured';
    const expectedSecretPrefix = this.mode === 'test' ? 'sk_test_' : 'sk_live_';
    if (!this.secretKey.startsWith(expectedSecretPrefix)) {
      return 'payment_key_mode_mismatch';
    }
    if (this.publicKey) {
      const expectedPublicPrefix = this.mode === 'test' ? 'pk_test_' : 'pk_live_';
      if (!this.publicKey.startsWith(expectedPublicPrefix)) {
        return 'payment_key_mode_mismatch';
      }
    }
    return null;
  }

  async initializeCheckout({
    email,
    amountMinor,
    currency,
    planCode,
    reference,
    callbackUrl,
    metadata,
  }) {
    return this.#request('/transaction/initialize', {
      method: 'POST',
      body: {
        email,
        amount: amountMinor,
        currency,
        plan: planCode,
        reference,
        callback_url: callbackUrl,
        metadata,
      },
    });
  }

  async verifyPayment(reference) {
    return this.#request(
      `/transaction/verify/${encodeURIComponent(reference)}`,
    );
  }

  async cancelRenewal({ subscriptionCode, emailToken }) {
    return this.#request('/subscription/disable', {
      method: 'POST',
      body: { code: subscriptionCode, token: emailToken },
    });
  }

  async reactivateSubscription({ subscriptionCode, emailToken }) {
    return this.#request('/subscription/enable', {
      method: 'POST',
      body: { code: subscriptionCode, token: emailToken },
    });
  }

  async #request(path, { method = 'GET', body } = {}) {
    if (!this.configured) {
      const error = new Error('Paystack payment configuration is unavailable.');
      error.code = this.configurationError;
      throw error;
    }
    const response = await this.fetchImpl(`https://api.paystack.co${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${this.secretKey}`,
        'Content-Type': 'application/json',
      },
      body: body == null ? undefined : JSON.stringify(body),
    });
    const payload = await response.json();
    if (!response.ok || payload.status !== true) {
      const error = new Error(payload.message ?? 'Paystack request failed.');
      error.code = 'gateway_request_failed';
      error.statusCode = response.status;
      throw error;
    }
    return payload.data;
  }
}
