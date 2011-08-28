BEGIN;

ALTER TABLE ONLY gadget_instance
    DROP CONSTRAINT default_gadget_id_fk,
    DROP COLUMN default_gadget_id;

-- Update schema version
UPDATE "System"
   SET value = '36'
 WHERE field = 'socialtext-schema-version';

COMMIT;
