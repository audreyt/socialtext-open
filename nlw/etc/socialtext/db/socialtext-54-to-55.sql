BEGIN;

CREATE TABLE account_logo (
    account_id bigint NOT NULL,
    logo bytea NOT NULL
);

ALTER TABLE account_logo
    ADD CONSTRAINT account_logo_pkey PRIMARY KEY (account_id),
    ADD CONSTRAINT account_logo_account_fk FOREIGN KEY (account_id)
        REFERENCES "Account"(account_id) ON DELETE CASCADE;

UPDATE "System"
   SET value = '55'
 WHERE field = 'socialtext-schema-version';

COMMIT;
