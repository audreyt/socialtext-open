BEGIN;

-- Update widgets to point to the widgets plugin rather than the gadgets
-- plugin
UPDATE storage
    SET value = REPLACE(value, '/usr/share/nlw/plugin/', '')
    WHERE key = 'file';

UPDATE "System"
   SET value = 11
 WHERE field = 'socialtext-schema-version';

COMMIT;
