BEGIN;

-- Swap sides for the explore widget and its filters

UPDATE gadget_instance
   SET col = 1
 WHERE EXISTS (
    SELECT 1 FROM gadget
     WHERE src = 'local:signals:explore'
       AND gadget_id = gadget_instance.gadget_id
 );

UPDATE gadget_instance
   SET col = 0
 WHERE EXISTS (
    SELECT 1 FROM gadget
     WHERE src = 'local:signals:explore_filters'
       AND gadget_id = gadget_instance.gadget_id
 );

UPDATE "System"
   SET value = '128'
 WHERE field = 'socialtext-schema-version';
COMMIT;
