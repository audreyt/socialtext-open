BEGIN;

CREATE TABLE account_theme_attachment (
    account_id bigint NOT NULL,
    attachment_id  integer NOT NULL
);

ALTER TABLE ONLY account_theme_attachment
    ADD CONSTRAINT account_theme_attachment_pkey
            PRIMARY KEY (account_id, attachment_id);

ALTER TABLE ONLY account_theme_attachment
    ADD CONSTRAINT theme_attachment_attachment_id_fk
            FOREIGN KEY (attachment_id)
            REFERENCES attachment(attachment_id) ON DELETE RESTRICT;

ALTER TABLE ONLY account_theme_attachment
    ADD CONSTRAINT theme_attachment_account_id_fk
            FOREIGN KEY (account_id)
            REFERENCES "Account"(account_id) ON DELETE RESTRICT;

UPDATE "System"
   SET value = '154'
 WHERE field = 'socialtext-schema-version';

COMMIT;
