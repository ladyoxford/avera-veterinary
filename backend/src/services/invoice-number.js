export function compactInvoiceNumber(submissionId, now = new Date()) {
  if (!(now instanceof Date) || Number.isNaN(now.getTime())) {
    throw new TypeError('Invoice creation date must be valid.');
  }
  if (
    typeof submissionId !== 'string' ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      submissionId,
    )
  ) {
    throw new TypeError('Invoice submission ID must be a valid UUID.');
  }
  const date = [
    String(now.getUTCFullYear()).slice(-2),
    String(now.getUTCMonth() + 1).padStart(2, '0'),
    String(now.getUTCDate()).padStart(2, '0'),
  ].join('');
  const token = submissionId.replaceAll('-', '').slice(0, 12).toUpperCase();
  return `INV-${date}-${token}`;
}
