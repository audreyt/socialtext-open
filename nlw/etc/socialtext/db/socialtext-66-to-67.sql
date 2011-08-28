BEGIN;

-- Create a WebHooks table

CREATE TABLE webhook (
    id bigint NOT NULL,
    creator_id bigint NOT NULL,
    class text NOT NULL,
    account_id bigint,
    workspace_id bigint,
    details_blob text DEFAULT '{}',
    url text NOT NULL
);

CREATE SEQUENCE "webhook___webhook_id"
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;

CREATE INDEX webhook__workspace_class_ix
        ON webhook (class);

CREATE INDEX webhook__class_workspace_ix
        ON webhook (class, workspace_id);

CREATE INDEX webhook__class_account_ix
        ON webhook (class, account_id);

ALTER TABLE ONLY webhook
    ADD CONSTRAINT webhook_user_id_fk
            FOREIGN KEY (creator_id)
            REFERENCES users(user_id) ON DELETE CASCADE;

ALTER TABLE ONLY webhook
    ADD CONSTRAINT webhook_workspace_id_fk
            FOREIGN KEY (workspace_id)
            REFERENCES "Workspace"(workspace_id) ON DELETE CASCADE;

ALTER TABLE ONLY webhook
    ADD CONSTRAINT webhook_account_id_fk
            FOREIGN KEY (account_id)
            REFERENCES "Account"(account_id) ON DELETE CASCADE;

UPDATE "System"
    SET value = '67'
  WHERE field = 'socialtext-schema-version';

COMMIT;
