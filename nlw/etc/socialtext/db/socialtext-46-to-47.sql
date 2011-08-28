BEGIN;

-- Ideally this would be in it's own schema.

--
-- Begin Schwartz schema
--
-- Created by: Michael Zedeler <michael@zedeler.dk>

CREATE TABLE funcmap (
        funcid SERIAL PRIMARY KEY NOT NULL,
        funcname       VARCHAR(255) NOT NULL,
        UNIQUE(funcname)
);

CREATE TABLE job (
        jobid           SERIAL PRIMARY KEY NOT NULL,
        funcid          INT NOT NULL,
        arg             BYTEA,
        uniqkey         VARCHAR(255) NULL,
        insert_time     INTEGER,
        run_after       INTEGER NOT NULL,
        grabbed_until   INTEGER NOT NULL,
        priority        SMALLINT,
        coalesce        VARCHAR(255),
        UNIQUE(funcid, uniqkey)
);

CREATE INDEX job_funcid_runafter ON job (funcid, run_after);
CREATE INDEX job_funcid_coalesce ON job (funcid, coalesce text_pattern_ops);
CREATE INDEX job_coalesce ON job (coalesce text_pattern_ops);

CREATE TABLE note (
        jobid           BIGINT NOT NULL,
        notekey         VARCHAR(255),
        PRIMARY KEY (jobid, notekey),
        value           BYTEA
);

CREATE TABLE error (
        error_time      INTEGER NOT NULL,
        jobid           BIGINT NOT NULL,
        message         VARCHAR(255) NOT NULL,
        funcid          INT NOT NULL DEFAULT 0
);

CREATE INDEX error_funcid_errortime ON error (funcid, error_time);
CREATE INDEX error_time ON error (error_time);
CREATE INDEX error_jobid ON error (jobid);

CREATE TABLE exitstatus (
        jobid           BIGINT PRIMARY KEY NOT NULL,
        funcid          INT NOT NULL DEFAULT 0,
        status          SMALLINT,
        completion_time INTEGER,
        delete_after    INTEGER
);

CREATE INDEX exitstatus_funcid ON exitstatus (funcid);
CREATE INDEX exitstatus_deleteafter ON exitstatus (delete_after);


UPDATE "System"
   SET value = '47'
 WHERE field = 'socialtext-schema-version';

COMMIT;
