-- Inventory categories describe what a product is, not whether it may be
-- invoiced. Repair records created while equipment and office supplies were
-- incorrectly marked as non-sellable by the mobile catalogue.
UPDATE inventory_products
   SET is_sellable = true,
       updated_at = now()
 WHERE deleted_at IS NULL
   AND is_sellable = false
   AND (
     lower(COALESCE(category_key, '')) IN (
       'medical_equipment',
       'laboratory_equipment',
       'general_equipment',
       'office_admin',
       'office_supplies'
     )
     OR lower(btrim(category)) IN (
       'medical equipment & instruments',
       'laboratory equipment',
       'office & administrative supplies'
     )
   );
