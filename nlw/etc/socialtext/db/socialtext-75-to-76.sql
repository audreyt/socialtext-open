BEGIN;

-- Add a type to accounts
ALTER TABLE "Account"
    ADD COLUMN "account_type" text NOT NULL DEFAULT 'Standard';

ALTER TABLE "Account"
    ADD COLUMN "restrict_to_domain" text NOT NULL DEFAULT '';

CREATE INDEX "Account__free_fifty_domain"
    ON "Account" (restrict_to_domain)
    WHERE account_type = 'Free 50';

UPDATE "System"
   SET value = '76'
 WHERE field = 'socialtext-schema-version';

COMMIT;
