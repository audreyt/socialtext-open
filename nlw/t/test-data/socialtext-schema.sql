SET client_encoding = 'UTF8';
SET check_function_bodies = false;
SET client_min_messages = warning;

SET search_path = public, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = false;

CREATE TABLE "Account" (
    account_id bigint NOT NULL,
    name varchar(250) NOT NULL,
    is_system_created boolean DEFAULT false NOT NULL
);

CREATE SEQUENCE "Account___account_id"
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;

CREATE TABLE "Permission" (
    permission_id integer NOT NULL,
    name varchar(50) NOT NULL
);

CREATE SEQUENCE "Permission___permission_id"
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;

CREATE TABLE "Role" (
    role_id integer NOT NULL,
    name varchar(20) NOT NULL,
    used_as_default boolean DEFAULT false NOT NULL
);

CREATE SEQUENCE "Role___role_id"
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;

CREATE TABLE "System" (
    field varchar(1024) NOT NULL,
    value varchar(1024) NOT NULL,
    last_update timestamptz DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE "User" (
    user_id bigint NOT NULL,
    username varchar(250) NOT NULL,
    email_address varchar(250) NOT NULL,
    "password" varchar(40) NOT NULL,
    first_name varchar(200) DEFAULT ''::varchar NOT NULL,
    last_name varchar(200) DEFAULT ''::varchar NOT NULL
);

CREATE TABLE "UserEmailConfirmation" (
    user_id bigint NOT NULL,
    sha1_hash varchar(27) NOT NULL,
    expiration_datetime timestamptz DEFAULT '-infinity'::timestamptz NOT NULL,
    is_password_change boolean DEFAULT false NOT NULL
);

CREATE TABLE "UserId" (
    system_unique_id bigint NOT NULL,
    driver_key varchar(250) NOT NULL,
    driver_unique_id varchar(250) NOT NULL,
    driver_username varchar(250)
);

CREATE SEQUENCE "UserId___system_unique_id"
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;

CREATE TABLE "UserMetadata" (
    user_id bigint NOT NULL,
    creation_datetime timestamptz DEFAULT now() NOT NULL,
    last_login_datetime timestamptz DEFAULT '-infinity'::timestamptz NOT NULL,
    email_address_at_import varchar(250),
    created_by_user_id bigint,
    is_business_admin boolean DEFAULT false NOT NULL,
    is_technical_admin boolean DEFAULT false NOT NULL,
    is_system_created boolean DEFAULT false NOT NULL
);

CREATE TABLE "UserWorkspaceRole" (
    user_id bigint NOT NULL,
    workspace_id bigint NOT NULL,
    role_id integer NOT NULL,
    is_selected boolean DEFAULT true NOT NULL
);

CREATE SEQUENCE "User___user_id"
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;

CREATE TABLE "Watchlist" (
    workspace_id bigint NOT NULL,
    user_id bigint NOT NULL,
    page_text_id varchar(255) NOT NULL
);

CREATE TABLE "Workspace" (
    workspace_id bigint NOT NULL,
    name varchar(30) NOT NULL,
    title text NOT NULL,
    logo_uri text DEFAULT '' NOT NULL,
    homepage_weblog text DEFAULT '' NOT NULL,
    email_addresses_are_hidden boolean DEFAULT false NOT NULL,
    unmasked_email_domain varchar(250) DEFAULT ''::varchar NOT NULL,
    prefers_incoming_html_email boolean DEFAULT false NOT NULL,
    incoming_email_placement varchar(10) DEFAULT 'bottom'::varchar NOT NULL,
    allows_html_wafl boolean DEFAULT true NOT NULL,
    email_notify_is_enabled boolean DEFAULT true NOT NULL,
    sort_weblogs_by_create boolean DEFAULT false NOT NULL,
    external_links_open_new_window boolean DEFAULT true NOT NULL,
    basic_search_only boolean DEFAULT false NOT NULL,
    enable_unplugged boolean DEFAULT false NOT NULL,
    skin_name varchar(30) DEFAULT 's2'::varchar NOT NULL,
    custom_title_label varchar(100) DEFAULT ''::varchar NOT NULL,
    header_logo_link_uri varchar(100) DEFAULT 'http://www.socialtext.com/'::varchar NOT NULL,
    show_welcome_message_below_logo boolean DEFAULT false NOT NULL,
    show_title_below_logo boolean DEFAULT true NOT NULL,
    comment_form_note_top text DEFAULT '' NOT NULL,
    comment_form_note_bottom text DEFAULT '' NOT NULL,
    comment_form_window_height bigint DEFAULT 200 NOT NULL,
    page_title_prefix varchar(100) DEFAULT ''::varchar NOT NULL,
    email_notification_from_address varchar(100) DEFAULT 'noreply@socialtext.com'::varchar NOT NULL,
    email_weblog_dot_address boolean DEFAULT false NOT NULL,
    comment_by_email boolean DEFAULT false NOT NULL,
    homepage_is_dashboard boolean DEFAULT true NOT NULL,
    creation_datetime timestamptz DEFAULT now() NOT NULL,
    account_id bigint NOT NULL,
    created_by_user_id bigint NOT NULL,
    restrict_invitation_to_search boolean DEFAULT false NOT NULL,
    invitation_filter varchar(100),
    invitation_template varchar(30) DEFAULT 'st'::varchar NOT NULL,
    customjs_uri text DEFAULT '' NOT NULL,
    customjs_name text DEFAULT '' NOT NULL,
    no_max_image_size boolean DEFAULT false NOT NULL,
    cascade_css boolean DEFAULT true NOT NULL,
    uploaded_skin boolean DEFAULT false NOT NULL
);

CREATE TABLE "WorkspaceBreadcrumb" (
    user_id bigint NOT NULL,
    workspace_id bigint NOT NULL,
    "timestamp" timestamptz DEFAULT now() NOT NULL
);

CREATE TABLE "WorkspaceCommentFormCustomField" (
    workspace_id bigint NOT NULL,
    field_name varchar(250) NOT NULL,
    field_order bigint NOT NULL
);

CREATE TABLE "WorkspacePingURI" (
    workspace_id bigint NOT NULL,
    uri varchar(250) NOT NULL
);

CREATE TABLE "WorkspaceRolePermission" (
    workspace_id bigint NOT NULL,
    role_id integer NOT NULL,
    permission_id integer NOT NULL
);

CREATE SEQUENCE "Workspace___workspace_id"
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;

CREATE TABLE search_set_workspaces (
    search_set_id bigint NOT NULL,
    workspace_id bigint NOT NULL
);

CREATE TABLE search_sets (
    search_set_id bigint NOT NULL,
    name varchar(40) NOT NULL,
    owner_user_id bigint NOT NULL
);

CREATE SEQUENCE search_sets___search_set_id
    START WITH 1
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;

CREATE TABLE sessions (
    id character(32) NOT NULL,
    a_session text NOT NULL,
    last_updated timestamptz NOT NULL
);

ALTER TABLE ONLY "Account"
    ADD CONSTRAINT "Account_pkey"
            PRIMARY KEY (account_id);

ALTER TABLE ONLY "Permission"
    ADD CONSTRAINT "Permission_pkey"
            PRIMARY KEY (permission_id);

ALTER TABLE ONLY "Role"
    ADD CONSTRAINT "Role_pkey"
            PRIMARY KEY (role_id);

ALTER TABLE ONLY "UserEmailConfirmation"
    ADD CONSTRAINT "UserEmailConfirmation_pkey"
            PRIMARY KEY (user_id);

ALTER TABLE ONLY "UserId"
    ADD CONSTRAINT "UserId_pkey"
            PRIMARY KEY (system_unique_id);

ALTER TABLE ONLY "UserMetadata"
    ADD CONSTRAINT "UserMetadata_pkey"
            PRIMARY KEY (user_id);

ALTER TABLE ONLY "UserWorkspaceRole"
    ADD CONSTRAINT "UserWorkspaceRole_pkey"
            PRIMARY KEY (user_id, workspace_id);

ALTER TABLE ONLY "User"
    ADD CONSTRAINT "User_pkey"
            PRIMARY KEY (user_id);

ALTER TABLE ONLY "Watchlist"
    ADD CONSTRAINT "Watchlist_pkey"
            PRIMARY KEY (workspace_id, user_id, page_text_id);

ALTER TABLE ONLY "WorkspaceBreadcrumb"
    ADD CONSTRAINT "WorkspaceBreadcrumb_pkey"
            PRIMARY KEY (user_id, workspace_id);

ALTER TABLE ONLY "WorkspaceCommentFormCustomField"
    ADD CONSTRAINT "WorkspaceCommentFormCustomField_pkey"
            PRIMARY KEY (workspace_id, field_name);

ALTER TABLE ONLY "WorkspacePingURI"
    ADD CONSTRAINT "WorkspacePingURI_pkey"
            PRIMARY KEY (workspace_id, uri);

ALTER TABLE ONLY "WorkspaceRolePermission"
    ADD CONSTRAINT "WorkspaceRolePermission_pkey"
            PRIMARY KEY (workspace_id, role_id, permission_id);

ALTER TABLE ONLY "Workspace"
    ADD CONSTRAINT "Workspace_pkey"
            PRIMARY KEY (workspace_id);

ALTER TABLE ONLY search_sets
    ADD CONSTRAINT search_sets_pkey
            PRIMARY KEY (search_set_id);

ALTER TABLE ONLY sessions
    ADD CONSTRAINT sessions_pkey
            PRIMARY KEY (id);

ALTER TABLE ONLY "System"
    ADD CONSTRAINT system_pkey
            PRIMARY KEY (field);

CREATE UNIQUE INDEX "Account___name"
            ON "Account" (name);

CREATE UNIQUE INDEX "Permission___name"
            ON "Permission" (name);

CREATE UNIQUE INDEX "Role___name"
            ON "Role" (name);

CREATE UNIQUE INDEX "UserEmailConfirmation___sha1_hash"
            ON "UserEmailConfirmation" (sha1_hash);

CREATE UNIQUE INDEX "UserId___driver_key___driver_key___driver_unique_id"
            ON "UserId" (driver_key, driver_unique_id);

CREATE UNIQUE INDEX "UserMetadata___user_id"
            ON "UserMetadata" (user_id);

CREATE UNIQUE INDEX "User___lower___email_address"
            ON "User" (lower((email_address)::text));

CREATE UNIQUE INDEX "User___lower___username"
            ON "User" (lower((username)::text));

CREATE UNIQUE INDEX "Workspace___lower___name"
            ON "Workspace" (lower((name)::text));

CREATE UNIQUE INDEX search_set_workspaces___search_set_id___search_set_id___workspa
            ON search_set_workspaces (search_set_id, workspace_id);

CREATE UNIQUE INDEX search_sets___owner_user_id___owner_user_id___name
            ON search_sets (owner_user_id, lower((name)::text));

ALTER TABLE ONLY "WorkspacePingURI"
    ADD CONSTRAINT fk_040b7e8582f72e5921dc071311fc4a5f
            FOREIGN KEY (workspace_id)
            REFERENCES "Workspace"(workspace_id) ON DELETE CASCADE;

ALTER TABLE ONLY "WorkspaceRolePermission"
    ADD CONSTRAINT fk_1541e9b047972328826e1731bc85d4b8
            FOREIGN KEY (role_id)
            REFERENCES "Role"(role_id) ON DELETE CASCADE;

ALTER TABLE ONLY "Workspace"
    ADD CONSTRAINT fk_251eb1be4c68e78c9e4b7799c9eed357
            FOREIGN KEY (created_by_user_id)
            REFERENCES "UserId"(system_unique_id) ON DELETE CASCADE;

ALTER TABLE ONLY "UserWorkspaceRole"
    ADD CONSTRAINT fk_2d35adae0767c6ef9bd03ed923bd2380
            FOREIGN KEY (user_id)
            REFERENCES "UserId"(system_unique_id) ON DELETE CASCADE;

ALTER TABLE ONLY "UserMetadata"
    ADD CONSTRAINT fk_51604686f50dc445f1d697a101a6a5cb
            FOREIGN KEY (user_id)
            REFERENCES "UserId"(system_unique_id) ON DELETE CASCADE;

ALTER TABLE ONLY "WorkspaceBreadcrumb"
    ADD CONSTRAINT fk_537b27b50b95eea3e12ec792db0553f5
            FOREIGN KEY (workspace_id)
            REFERENCES "Workspace"(workspace_id) ON DELETE CASCADE;

ALTER TABLE ONLY "WorkspaceBreadcrumb"
    ADD CONSTRAINT fk_55d1290a6baacca3b4fec189a739ab5b
            FOREIGN KEY (user_id)
            REFERENCES "UserId"(system_unique_id) ON DELETE CASCADE;

ALTER TABLE ONLY "UserEmailConfirmation"
    ADD CONSTRAINT fk_777ad60e2bff785f8ff5ece0f3fc95c8
            FOREIGN KEY (user_id)
            REFERENCES "UserId"(system_unique_id) ON DELETE CASCADE;

ALTER TABLE ONLY "WorkspaceRolePermission"
    ADD CONSTRAINT fk_82421c1ae80e2402c554a4bdec97ef4d
            FOREIGN KEY (permission_id)
            REFERENCES "Permission"(permission_id) ON DELETE CASCADE;

ALTER TABLE ONLY "Watchlist"
    ADD CONSTRAINT fk_82a2b3654e91cdeab69734a8a7e06fa0
            FOREIGN KEY (workspace_id)
            REFERENCES "Workspace"(workspace_id) ON DELETE CASCADE;

ALTER TABLE ONLY "WorkspaceCommentFormCustomField"
    ADD CONSTRAINT fk_84d598c9d334a863af733a2647d59189
            FOREIGN KEY (workspace_id)
            REFERENCES "Workspace"(workspace_id) ON DELETE CASCADE;

ALTER TABLE ONLY "UserWorkspaceRole"
    ADD CONSTRAINT fk_c00a18f1daca90d376037f946a0b3894
            FOREIGN KEY (workspace_id)
            REFERENCES "Workspace"(workspace_id) ON DELETE CASCADE;

ALTER TABLE ONLY "WorkspaceRolePermission"
    ADD CONSTRAINT fk_d9034c52d2999d62d24bd2cfa30ac457
            FOREIGN KEY (workspace_id)
            REFERENCES "Workspace"(workspace_id) ON DELETE CASCADE;

ALTER TABLE ONLY "UserWorkspaceRole"
    ADD CONSTRAINT userworkspacerole___role___role_id___role_id___n___1___1___0
            FOREIGN KEY (role_id)
            REFERENCES "Role"(role_id) ON DELETE CASCADE;

ALTER TABLE ONLY "Watchlist"
    ADD CONSTRAINT watchlist___userid___user_id___system_unique_id___n___1___1___0
            FOREIGN KEY (user_id)
            REFERENCES "UserId"(system_unique_id) ON DELETE CASCADE;

ALTER TABLE ONLY "Workspace"
    ADD CONSTRAINT workspace___account___account_id___account_id___n___1___1___0
            FOREIGN KEY (account_id)
            REFERENCES "Account"(account_id) ON DELETE CASCADE;


DELETE FROM "System" WHERE field = 'socialtext-schema-version';
INSERT INTO "System" VALUES ('socialtext-schema-version', '2');

