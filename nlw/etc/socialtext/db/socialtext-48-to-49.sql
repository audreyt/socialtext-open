BEGIN;

ALTER TABLE ONLY signal
    ADD COLUMN recipient_id bigint,
    ADD CONSTRAINT signal_recipient_fk
        FOREIGN KEY (recipient_id)
        REFERENCES users(user_id)
        ON DELETE CASCADE;

CREATE INDEX ix_signal_recipient_at
    ON signal (recipient_id, "at");

UPDATE "System"
   SET value = '49'
 WHERE field = 'socialtext-schema-version';

COMMIT;
