CREATE TABLE "WorkspaceBreadcrumb" (
    user_id bigint NOT NULL,
    workspace_id bigint NOT NULL,
    "timestamp" timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE ONLY "WorkspaceBreadcrumb"
    ADD CONSTRAINT "WorkspaceBreadcrumb_pkey"
            PRIMARY KEY (user_id, workspace_id);

ALTER TABLE ONLY "WorkspaceBreadcrumb"
    ADD CONSTRAINT fk_537b27b50b95eea3e12ec792db0553f5
            FOREIGN KEY (workspace_id)
            REFERENCES "Workspace"(workspace_id) ON DELETE CASCADE;

ALTER TABLE ONLY "WorkspaceBreadcrumb"
    ADD CONSTRAINT fk_55d1290a6baacca3b4fec189a739ab5b
            FOREIGN KEY (user_id)
            REFERENCES "UserId"(system_unique_id) ON DELETE CASCADE;
