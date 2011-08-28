BEGIN;

-- Create a table to store data in the caching json proxy
CREATE TABLE json_proxy_cache (
    expires timestamptz NOT NULL,
    user_id bigint NOT NULL,
    url TEXT NOT NULL,
    headers TEXT NOT NULL DEFAULT '',
    authz TEXT, -- not implemented
    content TEXT
);

ALTER TABLE ONLY json_proxy_cache
    ADD CONSTRAINT json_proxy_cache_user_id_fk
            FOREIGN KEY (user_id)
            REFERENCES users(user_id) ON DELETE CASCADE;

CREATE INDEX json_proxy_cache_idx 
        ON json_proxy_cache (url, headers);

UPDATE "System"
   SET value = '72'
 WHERE field = 'socialtext-schema-version';

COMMIT;
