BEGIN;

CREATE INDEX ix_job_piro_non_null ON job (COALESCE(priority,0));

UPDATE "System"
   SET value = '57'
 WHERE field = 'socialtext-schema-version';

COMMIT;
