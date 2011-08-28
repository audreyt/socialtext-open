BEGIN;

CREATE TABLE user_like (
    liker_user_id bigint NOT NULL,

    -- What's liked ?

    -- Page
    workspace_id bigint,
    page_id text,
    revision_id numeric(19,5), -- optional revision

    -- Signal
    signal_id bigint
);

UPDATE "System"
   SET value = '142'
 WHERE field = 'socialtext-schema-version';

COMMIT;
