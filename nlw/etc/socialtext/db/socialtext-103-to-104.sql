BEGIN;

--- Updates to the "recent signals" tables/indices from last week/iteration.

--- Remove "DELETE" trigger on the "recent_signal" table, instead using a
--- Foreign Key constraint back to the original "signal" table to do the work
--- for us.
DROP TRIGGER signal_delete_recent ON signal;
DROP FUNCTION delete_recent_signal();

ALTER TABLE ONLY "recent_signal"
    ADD CONSTRAINT recent_signal_signal_id
    FOREIGN KEY (signal_id)
    REFERENCES signal(signal_id) ON DELETE CASCADE;

--- Remove "DELETE" trigger on the "recent_signal_user_set" table, instead
--- using a Foreign Key constraint back to the original "signal_user_set"
--- table to do the work for us.
DROP TRIGGER signal_uset_delete_recent ON signal_user_set;
DROP FUNCTION delete_recent_signal_user_set();

ALTER TABLE ONLY "recent_signal_user_set"
    ADD CONSTRAINT recent_signal_uset_signal_user_set
    FOREIGN KEY (signal_id, user_set_id)
    REFERENCES signal_user_set(signal_id, user_set_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE;

--- Remove "UPDATE" trigger on the "recent_signal_user_set" table, instead
--- letting the above mentioned Foreign Key constraint keep things in check.
--- Being that the *only* two columns in this table are part of the foreign
--- key constraint, this'll work (as there's no other column that could get
--- updated that we'd need to have the trigger take care of for us).
DROP TRIGGER signal_uset_update_recent ON signal_user_set;
DROP FUNCTION update_recent_signal_user_set();

--- Add missing pkey index on the "recent_signal_user_set" table.
ALTER TABLE ONLY recent_signal_user_set
    ADD CONSTRAINT recent_signal_user_set_pkey
    PRIMARY KEY (signal_id, user_set_id);

--- DB migration done
UPDATE "System"
   SET value = '104'
 WHERE field = 'socialtext-schema-version';

COMMIT;
