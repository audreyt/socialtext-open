DROP INDEX "User___lower___username";

DROP INDEX "User___lower___email_address";

ALTER TABLE "UserEmailConfirmation"
  DROP CONSTRAINT fk_01f5155cd1b191ae80ac6ed2594f7774;

ALTER TABLE "UserWorkspaceRole"
  DROP CONSTRAINT userworkspacerole___user___user_id___user_id___n___1___1___0;

ALTER TABLE "Workspace"
  DROP CONSTRAINT workspace___user___created_by_user_id___user_id___n___1___1___0;

ALTER TABLE "User"
  DROP CONSTRAINT user___user___created_by_user_id___user_id___n___1___0___0;

ALTER TABLE "Watchlist"
  DROP CONSTRAINT watchlist___user___user_id___user_id___n___1___1___0;

ALTER TABLE "User" RENAME TO "ProtoUser";

CREATE TABLE "User" (
  "user_id"  INT8  NOT NULL,
  "username"  VARCHAR(250)  NOT NULL,
  "email_address"  VARCHAR(250)  NOT NULL,
  "password"  VARCHAR(40)  NOT NULL,
  "first_name"  VARCHAR(200)  DEFAULT ''  NOT NULL,
  "last_name"  VARCHAR(200)  DEFAULT ''  NOT NULL,
  PRIMARY KEY ("user_id")
);

CREATE UNIQUE INDEX "User___lower___username" ON "User" ( lower(username) );
CREATE UNIQUE INDEX "User___lower___email_address" ON "User" ( lower(email_address) );

CREATE TABLE "UserId" (
  "system_unique_id"  INT8  NOT NULL,
  "driver_key"  VARCHAR(250)  NOT NULL,
  "driver_unique_id"  VARCHAR(250)  NOT NULL,
  "driver_username"  VARCHAR(250)  NULL,
  PRIMARY KEY ("system_unique_id")
);

CREATE TABLE "UserMetadata" (
  "user_id"  INT8  NOT NULL,
  "creation_datetime"  TIMESTAMPTZ  DEFAULT CURRENT_TIMESTAMP  NOT NULL,
  "last_login_datetime"  TIMESTAMPTZ  DEFAULT '-infinity'  NOT NULL,
  "email_address_at_import"  VARCHAR(250)  NULL,
  "created_by_user_id"  INT8  NULL,
  "is_business_admin"  BOOLEAN  DEFAULT 'f'  NOT NULL,
  "is_technical_admin"  BOOLEAN  DEFAULT 'f'  NOT NULL,
  "is_system_created"  BOOLEAN  DEFAULT 'f'  NOT NULL,
  PRIMARY KEY ("user_id")
);

CREATE UNIQUE INDEX "UserMetadata___user_id" ON "UserMetadata" ( "user_id" );

INSERT INTO "User"
  (SELECT user_id, username, email_address, password,
    first_name, last_name
   FROM "ProtoUser");

INSERT INTO "UserMetadata"
  (SELECT user_id, creation_datetime, last_login_datetime,
    email_address_at_import, created_by_user_id, is_business_admin,
    is_technical_admin, is_system_created
    FROM "ProtoUser");

INSERT INTO "UserId"
  (SELECT user_id, 'Default', user_id, username
    FROM "ProtoUser");

CREATE SEQUENCE "UserId___system_unique_id";

SELECT setval('"UserId___system_unique_id"', max(system_unique_id))
  FROM "UserId";
