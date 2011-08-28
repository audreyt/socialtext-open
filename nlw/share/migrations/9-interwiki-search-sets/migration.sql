CREATE TABLE "search_sets" (
  "search_set_id"  INT8  NOT NULL,
  "name"  VARCHAR(40)  NOT NULL,
  "owner_user_id"  INT8  NOT NULL,
  PRIMARY KEY ("search_set_id")
);

CREATE UNIQUE INDEX "search_sets___owner_user_id___owner_user_id___name" ON "search_sets" ( owner_user_id, lower(name) );
CREATE SEQUENCE "search_sets___search_set_id";

CREATE TABLE "search_set_workspaces" (
  "search_set_id"  INT8  NOT NULL,
  "workspace_id"  INT8  NOT NULL);

CREATE UNIQUE INDEX "search_set_workspaces___search_set_id___search_set_id___workspace_id" ON "search_set_workspaces" ( search_set_id, workspace_id );
