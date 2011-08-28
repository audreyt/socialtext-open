BEGIN;

-- Found several missing indexes on TheSchwartz' tables that resulted in long
-- query times.  For example idx_job_func_coalesce_prio is for the "grab jobs
-- in the same class with the same coalescing key" that our CoalescingJob
-- Moose::Role executes.

CREATE INDEX idx_job_ready ON job (COALESCE(priority,0),grabbed_until,run_after);
CREATE INDEX idx_job_func_coalesce_prio ON job (funcid,coalesce,COALESCE(priority,0));
CREATE INDEX idx_job_ready_coalesce_prefix ON job (funcid,coalesce text_pattern_ops,grabbed_until,run_after);

UPDATE "System"
   SET value = '126'
 WHERE field = 'socialtext-schema-version';
COMMIT;
