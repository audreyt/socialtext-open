BEGIN;

-- reserved for Story: user can insert user mentions into signals

CREATE TABLE topic_signal_user (
    signal_id bigint NOT NULL,
    user_id bigint NOT NULL
);

ALTER TABLE topic_signal_user
    ADD CONSTRAINT topic_signal_user_pk PRIMARY KEY (signal_id,user_id);

CREATE INDEX ix_tsu_user ON topic_signal_user(user_id);

ALTER TABLE topic_signal_user
    ADD CONSTRAINT tsu_signal_fk
        FOREIGN KEY (signal_id)
        REFERENCES signal(signal_id) ON DELETE CASCADE,
    ADD CONSTRAINT tsu_user_fk
        FOREIGN KEY (user_id)
        REFERENCES users(user_id) ON DELETE CASCADE;

-- Story: user can reply to signals and view replies

ALTER TABLE signal
    ADD COLUMN in_reply_to_id bigint;

ALTER TABLE signal
    ADD CONSTRAINT in_reply_to_fk
        FOREIGN KEY (in_reply_to_id)
        REFERENCES signal(signal_id) ON DELETE CASCADE;

CREATE INDEX ix_signal_reply ON signal (in_reply_to_id);

UPDATE "System"
   SET value = '45'
 WHERE field = 'socialtext-schema-version';

COMMIT;
