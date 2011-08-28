BEGIN;

-- Clean up old search codes
DROP TABLE search_set_workspaces;
DROP TABLE search_sets;
DROP SEQUENCE search_sets___search_set_id;

COMMIT;
