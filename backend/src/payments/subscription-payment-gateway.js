export class SubscriptionPaymentGateway {
  async initializeCheckout() {
    throw new Error('initializeCheckout is not implemented.');
  }

  async verifyPayment() {
    throw new Error('verifyPayment is not implemented.');
  }

  async cancelRenewal() {
    throw new Error('cancelRenewal is not implemented.');
  }

  async reactivateSubscription() {
    throw new Error('reactivateSubscription is not implemented.');
  }
}
