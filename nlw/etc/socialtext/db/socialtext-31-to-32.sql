BEGIN;

-- Add a "topic" table that links signals to pages.

CREATE TABLE topic_signal_page (
    signal_id int NOT NULL,
    workspace_id int NOT NULL,
    page_id text NOT NULL
);

ALTER TABLE ONLY topic_signal_page
    ADD CONSTRAINT topic_signal_page_pk
            PRIMARY KEY (signal_id, workspace_id, page_id);

ALTER TABLE ONLY topic_signal_page
    ADD CONSTRAINT topic_signal_page_forward
            FOREIGN KEY (workspace_id, page_id)
            REFERENCES page (workspace_id, page_id) ON DELETE CASCADE;

ALTER TABLE ONLY topic_signal_page
    ADD CONSTRAINT topic_signal_page_reverse
            FOREIGN KEY (signal_id)
            REFERENCES signal (signal_id) ON DELETE CASCADE;

CREATE INDEX ix_topic_signal_page_forward 
            ON topic_signal_page (workspace_id, page_id);

CREATE INDEX ix_topic_signal_page_reverse 
            ON topic_signal_page (signal_id);

UPDATE "System"
    SET value = '32'
    WHERE field = 'socialtext-schema-version';

COMMIT;
