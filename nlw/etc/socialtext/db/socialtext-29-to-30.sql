BEGIN;

-- rename noun to signal and clean things up

    ALTER TABLE noun
        RENAME TO signal;

    ALTER TABLE signal
        RENAME COLUMN noun_id TO signal_id;
    ALTER TABLE signal
        DROP COLUMN noun_type;

    -- signal.body should never have been nullable.
    DELETE FROM signal WHERE body IS NULL;
    ALTER TABLE signal
        ALTER COLUMN body SET NOT NULL;

    -- think of this as RENAME PRIMARY KEY
    ALTER INDEX "noun_pkey" RENAME TO "signal_pkey";
    UPDATE pg_constraint
       SET conname = 'signal_pkey'
     WHERE conname = 'noun_pkey';

    -- think of this as RENAME CONSTRAINT
    UPDATE pg_constraint
       SET conname = 'signal_user_id_fk'
     WHERE conname = 'noun_user_id_fk';

    ALTER INDEX "ix_noun_at"      RENAME TO "ix_signal_at";
    ALTER INDEX "ix_noun_at_user" RENAME TO "ix_signal_at_user";
    ALTER INDEX "ix_noun_user_at" RENAME TO "ix_signal_user_at";

    -- think of this as RENAME SEQUENCE
    ALTER TABLE noun_id_seq RENAME TO signal_id_seq;

-- make the event table refer to the signal table explicitly.  A data
-- migration will pull the "noun_id" out of the context blob to complete the
-- linking

    ALTER TABLE event
        ADD COLUMN signal_id bigint;

    ALTER TABLE event
        ADD CONSTRAINT "event_signal_id_fk" 
        FOREIGN KEY (signal_id) 
        REFERENCES signal (signal_id)
        ON DELETE CASCADE;

-- stash predicts that this index will be useful
-- brandon thinks it will bring the heat-death of the universe closer (just kidding)

    CREATE INDEX "ix_event_signal_id_at"
        ON event (signal_id, "at");

UPDATE "System"
    SET value = 30
    WHERE field = 'socialtext-schema-version';

COMMIT;
