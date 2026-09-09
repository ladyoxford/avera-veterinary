-- Extend the existing ledger without changing any historical population or row.
ALTER TABLE farm_population_movements
  DROP CONSTRAINT farm_population_movements_movement_type_check;
ALTER TABLE farm_population_movements
  ADD CONSTRAINT farm_population_movements_movement_type_check
  CHECK (movement_type IN ('mortality', 'purchase', 'sale'));
