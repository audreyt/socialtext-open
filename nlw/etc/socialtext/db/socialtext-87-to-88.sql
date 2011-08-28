BEGIN;

-- Fix a condition created by {bz: 3200}

-- BACKGROUND:
-- Removing a socialtext-shipped 3rd aprty widget results in a second entry in
-- the gallery_gadget table with removed set to TRUE. (this is good)
-- Restoring those 3rd party widgets should result in that second entry being
-- removed, *however*, instead we were setting removed to FALSE. This results
-- in duplicate non-hidden widgets.

-- FIX:
-- Delete all entries that are socialtext-shipped (global), have removed set to
-- FALSE, and are not in the default gallery (0)
DELETE FROM gallery_gadget
 WHERE global
   AND NOT removed
   AND gallery_id > 0;

-- update the schema-version
UPDATE "System"
   SET value = '88'
 WHERE field = 'socialtext-schema-version';

COMMIT;
