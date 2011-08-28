BEGIN;

CREATE TABLE noun (
    noun_id bigint NOT NULL,
    noun_type text NOT NULL,
    at timestamptz DEFAULT now(),
    user_id bigint NOT NULL,
    body text
);

CREATE SEQUENCE noun_id_seq
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;

ALTER TABLE ONLY noun
    ADD CONSTRAINT noun_pkey
            PRIMARY KEY (noun_id);

ALTER TABLE ONLY noun
    ADD CONSTRAINT noun_user_id_fk
            FOREIGN KEY (user_id)
            REFERENCES users(user_id) ON DELETE CASCADE;

-- finish up

UPDATE "System"
   SET value = 19
 WHERE field = 'socialtext-schema-version';

COMMIT;
