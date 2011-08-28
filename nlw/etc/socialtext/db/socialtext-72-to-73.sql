BEGIN;

DELETE FROM json_proxy_cache;

DROP INDEX json_proxy_cache_idx;

ALTER TABLE json_proxy_cache
    DROP COLUMN expires,
    DROP COLUMN headers,
    ADD COLUMN key text NOT NULL,
    ADD COLUMN at timestamptz NOT NULL DEFAULT now(),
    ADD COLUMN refresh_interval interval NOT NULL DEFAULT '3600 seconds',
    ADD COLUMN expiry timestamptz NOT NULL;

CREATE UNIQUE INDEX json_proxy_cache_key_idx 
        ON json_proxy_cache (user_id, key);

CREATE INDEX json_proxy_cache_expiry_idx
        ON json_proxy_cache (expiry);

UPDATE "System"
   SET value = '73'
 WHERE field = 'socialtext-schema-version';

COMMIT;
