enum RevenueMetric {
  revenue('revenue', 'Revenue'),
  grossProfit('gross_profit', 'Gross Profit'),
  recordedCost('recorded_cost', 'Recorded Cost'),
  margin('margin', 'Margin'),
  clinicRevenue('clinic_revenue', 'Clinic Operations'),
  farmRevenue('farm_revenue', 'Farm Operations'),
  settledTransactions('settled_transactions', 'Settled Transactions');

  const RevenueMetric(this.apiValue, this.label);

  final String apiValue;
  final String label;
}
