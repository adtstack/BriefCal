import GRDB

enum DatabaseMigrations {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_context_store") { db in
            try db.execute(sql: """
                CREATE TABLE event_contexts (
                    id TEXT PRIMARY KEY NOT NULL,
                    title_snapshot TEXT NOT NULL,
                    start_snapshot TEXT,
                    end_snapshot TEXT,
                    lifecycle_status TEXT NOT NULL DEFAULT 'scheduled'
                        CHECK (lifecycle_status IN ('scheduled', 'completed', 'cancelled', 'orphaned')),
                    notes TEXT NOT NULL DEFAULT '',
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE event_links (
                    id TEXT PRIMARY KEY NOT NULL,
                    context_id TEXT NOT NULL UNIQUE
                        REFERENCES event_contexts(id) ON DELETE CASCADE,
                    event_identifier TEXT,
                    calendar_item_identifier TEXT,
                    calendar_item_external_identifier TEXT,
                    calendar_identifier TEXT NOT NULL,
                    source_title TEXT NOT NULL,
                    calendar_title_snapshot TEXT NOT NULL,
                    title_snapshot TEXT NOT NULL,
                    start_snapshot TEXT NOT NULL,
                    end_snapshot TEXT NOT NULL,
                    location_snapshot TEXT,
                    is_all_day BOOLEAN NOT NULL
                        CHECK (is_all_day IN (0, 1)),
                    is_recurring BOOLEAN NOT NULL
                        CHECK (is_recurring IN (0, 1)),
                    time_semantics TEXT NOT NULL
                        CHECK (time_semantics IN ('all_day', 'floating', 'zoned')),
                    time_zone_identifier TEXT,
                    start_local_components TEXT,
                    end_local_components TEXT,
                    recurrence_series_identifier TEXT,
                    occurrence_date TEXT,
                    occurrence_local_components TEXT,
                    occurrence_identity_key TEXT NOT NULL,
                    is_detached BOOLEAN NOT NULL
                        CHECK (is_detached IN (0, 1)),
                    fingerprint TEXT NOT NULL,
                    series_fingerprint TEXT,
                    link_status TEXT NOT NULL DEFAULT 'active'
                        CHECK (link_status IN ('active', 'missing', 'orphaned')),
                    last_seen_at TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    CHECK (
                        (time_semantics = 'all_day'
                            AND time_zone_identifier IS NULL
                            AND start_local_components IS NOT NULL
                            AND end_local_components IS NOT NULL)
                        OR
                        (time_semantics = 'floating'
                            AND time_zone_identifier IS NULL
                            AND start_local_components IS NOT NULL
                            AND end_local_components IS NOT NULL)
                        OR
                        (time_semantics = 'zoned'
                            AND time_zone_identifier IS NOT NULL
                            AND start_local_components IS NULL
                            AND end_local_components IS NULL)
                    ),
                    CHECK (
                        (is_all_day = 1 AND time_semantics = 'all_day')
                        OR (is_all_day = 0 AND time_semantics != 'all_day')
                    ),
                    CHECK (is_detached = 0 OR is_recurring = 1),
                    CHECK (
                        (is_recurring = 0
                            AND recurrence_series_identifier IS NULL
                            AND occurrence_date IS NULL
                            AND occurrence_local_components IS NULL
                            AND occurrence_identity_key = 'single:v1')
                        OR
                        (is_recurring = 1
                            AND occurrence_date IS NOT NULL
                            AND (
                                (time_semantics = 'zoned'
                                    AND occurrence_local_components IS NULL
                                    AND occurrence_identity_key LIKE 'instant:v1:%')
                                OR
                                (time_semantics != 'zoned'
                                    AND occurrence_local_components IS NOT NULL
                                    AND occurrence_identity_key =
                                        'local:v1:' || occurrence_local_components)
                            ))
                    )
                )
                """)

            try db.execute(sql: """
                CREATE TABLE event_tasks (
                    id TEXT PRIMARY KEY NOT NULL,
                    context_id TEXT NOT NULL
                        REFERENCES event_contexts(id) ON DELETE CASCADE,
                    section TEXT NOT NULL
                        CHECK (section IN ('before', 'during', 'after')),
                    title TEXT NOT NULL,
                    completed BOOLEAN NOT NULL DEFAULT 0
                        CHECK (completed IN (0, 1)),
                    sort_order INTEGER NOT NULL,
                    due_kind TEXT NOT NULL DEFAULT 'none'
                        CHECK (due_kind IN ('none', 'relative', 'fixed')),
                    relative_anchor TEXT
                        CHECK (relative_anchor IS NULL OR relative_anchor IN (
                            'before_start', 'at_start', 'at_end', 'after_end'
                        )),
                    offset_minutes INTEGER,
                    fixed_due_at TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    completed_at TEXT,
                    CHECK (
                        (completed = 0 AND completed_at IS NULL)
                        OR (completed = 1 AND completed_at IS NOT NULL)
                    ),
                    CHECK (
                        (due_kind = 'none'
                            AND relative_anchor IS NULL
                            AND offset_minutes IS NULL
                            AND fixed_due_at IS NULL)
                        OR
                        (due_kind = 'fixed'
                            AND relative_anchor IS NULL
                            AND offset_minutes IS NULL
                            AND fixed_due_at IS NOT NULL)
                        OR
                        (due_kind = 'relative'
                            AND relative_anchor IS NOT NULL
                            AND offset_minutes IS NOT NULL
                            AND offset_minutes >= 0
                            AND offset_minutes <= 2628000
                            AND fixed_due_at IS NULL
                            AND (
                                relative_anchor IN ('before_start', 'after_end')
                                OR offset_minutes = 0
                            ))
                    )
                )
                """)

            try db.execute(sql: """
                CREATE TABLE personal_tasks (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL,
                    notes TEXT NOT NULL DEFAULT '',
                    due_at TEXT,
                    completed BOOLEAN NOT NULL DEFAULT 0
                        CHECK (completed IN (0, 1)),
                    sort_order INTEGER NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    completed_at TEXT,
                    CHECK (
                        (completed = 0 AND completed_at IS NULL)
                        OR (completed = 1 AND completed_at IS NOT NULL)
                    )
                )
                """)

            try db.execute(sql: """
                CREATE INDEX event_links_event_identifier
                    ON event_links(event_identifier);
                CREATE INDEX event_links_calendar_item_identifier
                    ON event_links(calendar_item_identifier);
                CREATE INDEX event_links_external_occurrence
                    ON event_links(
                        calendar_identifier,
                        calendar_item_external_identifier,
                        occurrence_identity_key
                    );
                CREATE INDEX event_links_series_occurrence
                    ON event_links(
                        calendar_identifier,
                        recurrence_series_identifier,
                        occurrence_identity_key
                    );
                CREATE INDEX event_links_snapshot
                    ON event_links(
                        calendar_identifier,
                        start_snapshot,
                        end_snapshot
                    );
                CREATE INDEX event_links_fingerprint
                    ON event_links(fingerprint);
                CREATE INDEX event_links_series_fingerprint
                    ON event_links(series_fingerprint);
                CREATE UNIQUE INDEX event_links_unique_event_occurrence
                    ON event_links(
                        calendar_identifier,
                        event_identifier,
                        occurrence_identity_key
                    )
                    WHERE event_identifier IS NOT NULL
                        AND event_identifier != '';
                CREATE UNIQUE INDEX event_links_unique_item_occurrence
                    ON event_links(
                        calendar_identifier,
                        calendar_item_identifier,
                        occurrence_identity_key
                    )
                    WHERE calendar_item_identifier IS NOT NULL
                        AND calendar_item_identifier != '';
                CREATE UNIQUE INDEX event_links_unique_external_occurrence
                    ON event_links(
                        calendar_identifier,
                        calendar_item_external_identifier,
                        occurrence_identity_key
                    )
                    WHERE calendar_item_external_identifier IS NOT NULL
                        AND calendar_item_external_identifier != '';
                CREATE INDEX event_tasks_context_section_order
                    ON event_tasks(context_id, section, sort_order);
                CREATE INDEX personal_tasks_completion_due_order
                    ON personal_tasks(completed, due_at, sort_order);
                """)
        }

        migrator.registerMigration("v2_event_change_log") { db in
            try db.execute(sql: """
                CREATE TABLE event_change_log (
                    id TEXT PRIMARY KEY NOT NULL,
                    context_id TEXT NOT NULL
                        REFERENCES event_contexts(id) ON DELETE CASCADE,
                    change_type TEXT NOT NULL
                        CHECK (change_type IN (
                            'created', 'details_updated', 'moved',
                            'recurrence_changed', 'cancelled', 'completed',
                            'restored', 'relinked'
                        )),
                    scope TEXT NOT NULL
                        CHECK (scope IN (
                            'single', 'this_event', 'future_events'
                        )),
                    before_payload TEXT NOT NULL
                        CHECK (length(before_payload) > 0),
                    after_payload TEXT NOT NULL
                        CHECK (length(after_payload) > 0),
                    undo_state TEXT NOT NULL
                        CHECK (undo_state IN (
                            'available', 'superseded', 'undone', 'unavailable'
                        )),
                    undone_at TEXT,
                    undo_of_change_id TEXT
                        REFERENCES event_change_log(id) ON DELETE CASCADE,
                    created_at TEXT NOT NULL,
                    CHECK (
                        (undo_state = 'undone' AND undone_at IS NOT NULL)
                        OR (undo_state != 'undone' AND undone_at IS NULL)
                    ),
                    CHECK (
                        (change_type = 'restored'
                            AND undo_of_change_id IS NOT NULL
                            AND undo_state = 'unavailable')
                        OR (change_type != 'restored'
                            AND undo_of_change_id IS NULL)
                    )
                );
                CREATE INDEX event_change_log_context_created
                    ON event_change_log(context_id, created_at DESC);
                CREATE UNIQUE INDEX event_change_log_unique_undo
                    ON event_change_log(undo_of_change_id)
                    WHERE undo_of_change_id IS NOT NULL;
                """)
        }

        migrator.registerMigration("v3_calendar_clarity") { db in
            try db.execute(sql: """
                CREATE TABLE calendar_preferences (
                    calendar_identifier TEXT PRIMARY KEY NOT NULL
                        CHECK (length(trim(calendar_identifier)) > 0),
                    source_title_snapshot TEXT NOT NULL,
                    calendar_title_snapshot TEXT NOT NULL,
                    role TEXT NOT NULL
                        CHECK (role IN (
                            'work', 'personal', 'family', 'shared',
                            'subscription', 'other'
                        )),
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE INDEX calendar_preferences_role
                    ON calendar_preferences(role);
                """)
        }

        migrator.registerMigration("v4_task_provider") { db in
            try db.execute(sql: """
                CREATE TABLE provider_accounts (
                    id TEXT PRIMARY KEY NOT NULL,
                    provider TEXT NOT NULL
                        CHECK (provider IN ('apple_reminders')),
                    account_key TEXT NOT NULL UNIQUE,
                    display_name TEXT NOT NULL,
                    authorization_state TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE provider_items (
                    id TEXT PRIMARY KEY NOT NULL,
                    account_id TEXT NOT NULL
                        REFERENCES provider_accounts(id) ON DELETE CASCADE,
                    entity_type TEXT NOT NULL
                        CHECK (entity_type IN ('task')),
                    remote_id TEXT NOT NULL,
                    remote_parent_id TEXT NOT NULL,
                    remote_version TEXT,
                    cached_title TEXT NOT NULL,
                    cached_notes TEXT NOT NULL DEFAULT '',
                    cached_due_at TEXT,
                    cached_completed BOOLEAN NOT NULL DEFAULT 0
                        CHECK (cached_completed IN (0, 1)),
                    last_seen_at TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    UNIQUE(account_id, entity_type, remote_id)
                );

                CREATE TABLE task_bindings (
                    id TEXT PRIMARY KEY NOT NULL,
                    provider_item_id TEXT NOT NULL UNIQUE
                        REFERENCES provider_items(id) ON DELETE CASCADE,
                    event_task_id TEXT
                        REFERENCES event_tasks(id) ON DELETE CASCADE,
                    personal_task_id TEXT
                        REFERENCES personal_tasks(id) ON DELETE CASCADE,
                    occurrence_key TEXT,
                    sync_state TEXT NOT NULL
                        CHECK (sync_state IN (
                            'pending_create', 'linked', 'missing',
                            'conflict', 'disconnected'
                        )),
                    last_synced_hash TEXT,
                    remote_version TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    CHECK (
                        (event_task_id IS NOT NULL AND personal_task_id IS NULL)
                        OR (event_task_id IS NULL AND personal_task_id IS NOT NULL)
                    )
                );

                CREATE TABLE calendar_task_destinations (
                    calendar_identifier TEXT PRIMARY KEY NOT NULL,
                    provider_account_id TEXT NOT NULL
                        REFERENCES provider_accounts(id) ON DELETE CASCADE,
                    remote_parent_id TEXT NOT NULL,
                    enabled BOOLEAN NOT NULL DEFAULT 1
                        CHECK (enabled IN (0, 1)),
                    fallback_to_local BOOLEAN NOT NULL DEFAULT 1
                        CHECK (fallback_to_local IN (0, 1)),
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE UNIQUE INDEX task_bindings_event_task
                    ON task_bindings(event_task_id)
                    WHERE event_task_id IS NOT NULL;
                CREATE UNIQUE INDEX task_bindings_personal_task
                    ON task_bindings(personal_task_id)
                    WHERE personal_task_id IS NOT NULL;
                CREATE INDEX provider_items_account_parent
                    ON provider_items(account_id, remote_parent_id);
                CREATE INDEX task_bindings_state
                    ON task_bindings(sync_state);
            """)
        }

        // v4 deliberately shipped with Apple Reminders as its sole provider.
        // Rebuild the provider tables as one FK-connected unit so existing
        // local bindings remain valid while OAuth providers can be persisted.
        migrator.registerMigration("v5_oauth_task_providers") { db in
            try db.execute(sql: """
                ALTER TABLE task_bindings RENAME TO task_bindings_v4;
                ALTER TABLE calendar_task_destinations
                    RENAME TO calendar_task_destinations_v4;
                ALTER TABLE provider_items RENAME TO provider_items_v4;
                ALTER TABLE provider_accounts RENAME TO provider_accounts_v4;
                DROP INDEX task_bindings_event_task;
                DROP INDEX task_bindings_personal_task;
                DROP INDEX provider_items_account_parent;
                DROP INDEX task_bindings_state;

                CREATE TABLE provider_accounts (
                    id TEXT PRIMARY KEY NOT NULL,
                    provider TEXT NOT NULL
                        CHECK (provider IN (
                            'apple_reminders', 'google_tasks', 'todoist'
                        )),
                    account_key TEXT NOT NULL,
                    display_name TEXT NOT NULL,
                    authorization_state TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    UNIQUE(provider, account_key)
                );

                CREATE TABLE provider_items (
                    id TEXT PRIMARY KEY NOT NULL,
                    account_id TEXT NOT NULL
                        REFERENCES provider_accounts(id) ON DELETE CASCADE,
                    entity_type TEXT NOT NULL
                        CHECK (entity_type IN ('task')),
                    remote_id TEXT NOT NULL,
                    remote_parent_id TEXT NOT NULL,
                    remote_version TEXT,
                    cached_title TEXT NOT NULL,
                    cached_notes TEXT NOT NULL DEFAULT '',
                    cached_due_at TEXT,
                    cached_completed BOOLEAN NOT NULL DEFAULT 0
                        CHECK (cached_completed IN (0, 1)),
                    last_seen_at TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    UNIQUE(account_id, entity_type, remote_id)
                );

                CREATE TABLE task_bindings (
                    id TEXT PRIMARY KEY NOT NULL,
                    provider_item_id TEXT NOT NULL UNIQUE
                        REFERENCES provider_items(id) ON DELETE CASCADE,
                    event_task_id TEXT
                        REFERENCES event_tasks(id) ON DELETE CASCADE,
                    personal_task_id TEXT
                        REFERENCES personal_tasks(id) ON DELETE CASCADE,
                    occurrence_key TEXT,
                    sync_state TEXT NOT NULL
                        CHECK (sync_state IN (
                            'pending_create', 'linked', 'missing',
                            'conflict', 'disconnected'
                        )),
                    last_synced_hash TEXT,
                    remote_version TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    CHECK (
                        (event_task_id IS NOT NULL AND personal_task_id IS NULL)
                        OR (event_task_id IS NULL AND personal_task_id IS NOT NULL)
                    )
                );

                CREATE TABLE calendar_task_destinations (
                    calendar_identifier TEXT PRIMARY KEY NOT NULL,
                    provider_account_id TEXT NOT NULL
                        REFERENCES provider_accounts(id) ON DELETE CASCADE,
                    remote_parent_id TEXT NOT NULL,
                    enabled BOOLEAN NOT NULL DEFAULT 1
                        CHECK (enabled IN (0, 1)),
                    fallback_to_local BOOLEAN NOT NULL DEFAULT 1
                        CHECK (fallback_to_local IN (0, 1)),
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE provider_sync_cursors (
                    account_id TEXT NOT NULL
                        REFERENCES provider_accounts(id) ON DELETE CASCADE,
                    cursor_key TEXT NOT NULL,
                    cursor_value TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    PRIMARY KEY (account_id, cursor_key)
                );

                CREATE TABLE provider_pending_operations (
                    id TEXT PRIMARY KEY NOT NULL,
                    account_id TEXT NOT NULL
                        REFERENCES provider_accounts(id) ON DELETE CASCADE,
                    operation TEXT NOT NULL
                        CHECK (operation IN ('delete')),
                    remote_id TEXT NOT NULL,
                    remote_parent_id TEXT NOT NULL,
                    expected_version TEXT,
                    attempt_count INTEGER NOT NULL DEFAULT 0,
                    last_error TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                INSERT INTO provider_accounts (
                    id, provider, account_key, display_name,
                    authorization_state, created_at, updated_at
                )
                SELECT id, provider, account_key, display_name,
                    authorization_state, created_at, updated_at
                FROM provider_accounts_v4;

                INSERT INTO provider_items (
                    id, account_id, entity_type, remote_id, remote_parent_id,
                    remote_version, cached_title, cached_notes, cached_due_at,
                    cached_completed, last_seen_at, created_at, updated_at
                )
                SELECT id, account_id, entity_type, remote_id, remote_parent_id,
                    remote_version, cached_title, '', cached_due_at,
                    cached_completed, last_seen_at, created_at, updated_at
                FROM provider_items_v4;

                INSERT INTO task_bindings (
                    id, provider_item_id, event_task_id, personal_task_id,
                    occurrence_key, sync_state, last_synced_hash,
                    remote_version, created_at, updated_at
                )
                SELECT id, provider_item_id, event_task_id, personal_task_id,
                    occurrence_key, sync_state, last_synced_hash,
                    remote_version, created_at, updated_at
                FROM task_bindings_v4;

                INSERT INTO calendar_task_destinations (
                    calendar_identifier, provider_account_id, remote_parent_id,
                    enabled, fallback_to_local, created_at, updated_at
                )
                SELECT calendar_identifier, provider_account_id, remote_parent_id,
                    enabled, fallback_to_local, created_at, updated_at
                FROM calendar_task_destinations_v4;

                DROP TABLE task_bindings_v4;
                DROP TABLE calendar_task_destinations_v4;
                DROP TABLE provider_items_v4;
                DROP TABLE provider_accounts_v4;

                CREATE UNIQUE INDEX task_bindings_event_task
                    ON task_bindings(event_task_id)
                    WHERE event_task_id IS NOT NULL;
                CREATE UNIQUE INDEX task_bindings_personal_task
                    ON task_bindings(personal_task_id)
                    WHERE personal_task_id IS NOT NULL;
                CREATE INDEX provider_items_account_parent
                    ON provider_items(account_id, remote_parent_id);
                CREATE INDEX task_bindings_state
                    ON task_bindings(sync_state);
                CREATE INDEX provider_pending_operations_account
                    ON provider_pending_operations(account_id, updated_at);
            """)
        }
        migrator.registerMigration("v6_context_references") { db in
            try db.execute(sql: """
                CREATE TABLE context_references (
                    id TEXT PRIMARY KEY NOT NULL,
                    context_id TEXT NOT NULL
                        REFERENCES event_contexts(id) ON DELETE CASCADE,
                    provider TEXT NOT NULL CHECK (provider IN ('web', 'notion')),
                    url TEXT NOT NULL,
                    title_cache TEXT NOT NULL DEFAULT '',
                    state TEXT NOT NULL CHECK (state IN (
                        'active', 'missing', 'permission_required', 'disconnected'
                    )),
                    last_checked_at TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    UNIQUE(context_id, url)
                );
                CREATE INDEX context_references_context ON context_references(context_id, created_at);
            """)
        }
        migrator.registerMigration("v7_microsoft_to_do_provider") { db in
            try db.execute(sql: """
                ALTER TABLE task_bindings RENAME TO task_bindings_v6;
                ALTER TABLE calendar_task_destinations RENAME TO calendar_task_destinations_v6;
                ALTER TABLE provider_pending_operations RENAME TO provider_pending_operations_v6;
                ALTER TABLE provider_sync_cursors RENAME TO provider_sync_cursors_v6;
                ALTER TABLE provider_items RENAME TO provider_items_v6;
                ALTER TABLE provider_accounts RENAME TO provider_accounts_v6;
                DROP INDEX task_bindings_event_task;
                DROP INDEX task_bindings_personal_task;
                DROP INDEX provider_items_account_parent;
                DROP INDEX task_bindings_state;
                DROP INDEX provider_pending_operations_account;

                CREATE TABLE provider_accounts (
                    id TEXT PRIMARY KEY NOT NULL,
                    provider TEXT NOT NULL CHECK (provider IN ('apple_reminders', 'google_tasks', 'todoist', 'microsoft_to_do')),
                    account_key TEXT NOT NULL, display_name TEXT NOT NULL,
                    authorization_state TEXT NOT NULL, created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL, UNIQUE(provider, account_key)
                );
                CREATE TABLE provider_items (
                    id TEXT PRIMARY KEY NOT NULL,
                    account_id TEXT NOT NULL REFERENCES provider_accounts(id) ON DELETE CASCADE,
                    entity_type TEXT NOT NULL CHECK (entity_type IN ('task')),
                    remote_id TEXT NOT NULL, remote_parent_id TEXT NOT NULL,
                    remote_version TEXT, cached_title TEXT NOT NULL,
                    cached_notes TEXT NOT NULL DEFAULT '', cached_due_at TEXT,
                    cached_completed BOOLEAN NOT NULL DEFAULT 0 CHECK (cached_completed IN (0, 1)),
                    last_seen_at TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
                    UNIQUE(account_id, entity_type, remote_id)
                );
                CREATE TABLE task_bindings (
                    id TEXT PRIMARY KEY NOT NULL,
                    provider_item_id TEXT NOT NULL UNIQUE REFERENCES provider_items(id) ON DELETE CASCADE,
                    event_task_id TEXT REFERENCES event_tasks(id) ON DELETE CASCADE,
                    personal_task_id TEXT REFERENCES personal_tasks(id) ON DELETE CASCADE,
                    occurrence_key TEXT, sync_state TEXT NOT NULL CHECK (sync_state IN ('pending_create','linked','missing','conflict','disconnected')),
                    last_synced_hash TEXT, remote_version TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
                    CHECK ((event_task_id IS NOT NULL AND personal_task_id IS NULL) OR (event_task_id IS NULL AND personal_task_id IS NOT NULL))
                );
                CREATE TABLE calendar_task_destinations (
                    calendar_identifier TEXT PRIMARY KEY NOT NULL,
                    provider_account_id TEXT NOT NULL REFERENCES provider_accounts(id) ON DELETE CASCADE,
                    remote_parent_id TEXT NOT NULL, enabled BOOLEAN NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
                    fallback_to_local BOOLEAN NOT NULL DEFAULT 1 CHECK (fallback_to_local IN (0,1)),
                    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
                );
                CREATE TABLE provider_sync_cursors (
                    account_id TEXT NOT NULL REFERENCES provider_accounts(id) ON DELETE CASCADE,
                    cursor_key TEXT NOT NULL, cursor_value TEXT NOT NULL, updated_at TEXT NOT NULL,
                    PRIMARY KEY (account_id, cursor_key)
                );
                CREATE TABLE provider_pending_operations (
                    id TEXT PRIMARY KEY NOT NULL,
                    account_id TEXT NOT NULL REFERENCES provider_accounts(id) ON DELETE CASCADE,
                    operation TEXT NOT NULL CHECK (operation IN ('delete')),
                    remote_id TEXT NOT NULL, remote_parent_id TEXT NOT NULL, expected_version TEXT,
                    attempt_count INTEGER NOT NULL DEFAULT 0, last_error TEXT,
                    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
                );

                INSERT INTO provider_accounts SELECT * FROM provider_accounts_v6;
                INSERT INTO provider_items SELECT * FROM provider_items_v6;
                INSERT INTO task_bindings SELECT * FROM task_bindings_v6;
                INSERT INTO calendar_task_destinations SELECT * FROM calendar_task_destinations_v6;
                INSERT INTO provider_sync_cursors SELECT * FROM provider_sync_cursors_v6;
                INSERT INTO provider_pending_operations SELECT * FROM provider_pending_operations_v6;
                DROP TABLE task_bindings_v6; DROP TABLE calendar_task_destinations_v6;
                DROP TABLE provider_pending_operations_v6; DROP TABLE provider_sync_cursors_v6;
                DROP TABLE provider_items_v6; DROP TABLE provider_accounts_v6;
                CREATE UNIQUE INDEX task_bindings_event_task ON task_bindings(event_task_id) WHERE event_task_id IS NOT NULL;
                CREATE UNIQUE INDEX task_bindings_personal_task ON task_bindings(personal_task_id) WHERE personal_task_id IS NOT NULL;
                CREATE INDEX provider_items_account_parent ON provider_items(account_id, remote_parent_id);
                CREATE INDEX task_bindings_state ON task_bindings(sync_state);
                CREATE INDEX provider_pending_operations_account ON provider_pending_operations(account_id, updated_at);
            """)
        }
        migrator.registerMigration("v8_calendar_usage") { db in
            try db.execute(sql: """
                CREATE TABLE calendar_usage_preferences (
                    calendar_identifier TEXT PRIMARY KEY NOT NULL
                        CHECK (length(trim(calendar_identifier)) > 0),
                    source_identifier_snapshot TEXT NOT NULL,
                    source_title_snapshot TEXT NOT NULL,
                    calendar_title_snapshot TEXT NOT NULL,
                    visibility_override BOOLEAN
                        CHECK (visibility_override IS NULL
                            OR visibility_override IN (0, 1)),
                    blocking_override BOOLEAN
                        CHECK (blocking_override IS NULL
                            OR blocking_override IN (0, 1)),
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    CHECK (
                        visibility_override IS NOT NULL
                        OR blocking_override IS NOT NULL
                    )
                );
                CREATE INDEX calendar_usage_preferences_source
                    ON calendar_usage_preferences(source_identifier_snapshot);
            """)
        }
        migrator.registerMigration("v9_saved_calendar_sets") { db in
            try db.execute(sql: """
                CREATE TABLE calendar_sets (
                    id TEXT PRIMARY KEY NOT NULL
                        CHECK (length(trim(id)) > 0),
                    name TEXT NOT NULL COLLATE NOCASE UNIQUE
                        CHECK (length(trim(name)) BETWEEN 1 AND 80),
                    sort_order INTEGER NOT NULL
                        CHECK (sort_order >= 0),
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE INDEX calendar_sets_order
                    ON calendar_sets(sort_order, created_at, id);

                CREATE TABLE calendar_set_memberships (
                    id TEXT PRIMARY KEY NOT NULL
                        CHECK (length(trim(id)) > 0),
                    calendar_set_id TEXT NOT NULL
                        REFERENCES calendar_sets(id) ON DELETE CASCADE,
                    calendar_identifier TEXT NOT NULL
                        CHECK (length(trim(calendar_identifier)) > 0),
                    source_identifier_snapshot TEXT NOT NULL,
                    source_title_snapshot TEXT NOT NULL,
                    calendar_title_snapshot TEXT NOT NULL,
                    sort_order INTEGER NOT NULL
                        CHECK (sort_order >= 0),
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    UNIQUE(calendar_set_id, calendar_identifier)
                );
                CREATE INDEX calendar_set_memberships_set_order
                    ON calendar_set_memberships(
                        calendar_set_id, sort_order, created_at, id
                    );
                CREATE INDEX calendar_set_memberships_calendar
                    ON calendar_set_memberships(calendar_identifier);

                CREATE TABLE calendar_set_selection (
                    singleton_id INTEGER PRIMARY KEY NOT NULL
                        CHECK (singleton_id = 1),
                    selection_kind TEXT NOT NULL
                        CHECK (selection_kind IN ('role', 'saved')),
                    role TEXT
                        CHECK (role IS NULL OR role IN (
                            'work', 'personal', 'family', 'shared',
                            'subscription', 'other'
                        )),
                    calendar_set_id TEXT
                        REFERENCES calendar_sets(id) ON DELETE CASCADE,
                    updated_at TEXT NOT NULL,
                    CHECK (
                        (
                            selection_kind = 'role'
                            AND role IS NOT NULL
                            AND calendar_set_id IS NULL
                        )
                        OR (
                            selection_kind = 'saved'
                            AND role IS NULL
                            AND calendar_set_id IS NOT NULL
                        )
                    )
                );
            """)
        }
        migrator.registerMigration("v10_task_provider_recovery") { db in
            try db.execute(sql: """
                ALTER TABLE provider_pending_operations
                    RENAME TO provider_pending_operations_v9;
                DROP INDEX provider_pending_operations_account;

                CREATE TABLE provider_pending_operations (
                    id TEXT PRIMARY KEY NOT NULL,
                    account_id TEXT NOT NULL
                        REFERENCES provider_accounts(id) ON DELETE CASCADE,
                    event_task_id TEXT NOT NULL UNIQUE
                        REFERENCES event_tasks(id) ON DELETE CASCADE,
                    operation TEXT NOT NULL
                        CHECK (operation IN ('create', 'update', 'delete')),
                    remote_id TEXT,
                    remote_parent_id TEXT NOT NULL,
                    expected_version TEXT,
                    attempt_count INTEGER NOT NULL DEFAULT 0
                        CHECK (attempt_count BETWEEN 0 AND 3),
                    last_error TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    CHECK (
                        (operation = 'create' AND remote_id IS NULL)
                        OR (operation != 'create' AND remote_id IS NOT NULL)
                    )
                );

                INSERT INTO provider_pending_operations (
                    id, account_id, event_task_id, operation, remote_id,
                    remote_parent_id, expected_version, attempt_count,
                    last_error, created_at, updated_at
                )
                SELECT pending.id, pending.account_id, binding.event_task_id,
                    'delete', pending.remote_id, pending.remote_parent_id,
                    pending.expected_version,
                    MAX(0, MIN(pending.attempt_count, 3)), pending.last_error,
                    pending.created_at, pending.updated_at
                FROM provider_pending_operations_v9 AS pending
                INNER JOIN provider_items AS item
                    ON item.account_id = pending.account_id
                    AND item.remote_id = pending.remote_id
                    AND item.remote_parent_id = pending.remote_parent_id
                INNER JOIN task_bindings AS binding
                    ON binding.provider_item_id = item.id
                WHERE binding.event_task_id IS NOT NULL
                  AND pending.rowid = (
                    SELECT candidate.rowid
                    FROM provider_pending_operations_v9 AS candidate
                    INNER JOIN provider_items AS candidate_item
                        ON candidate_item.account_id = candidate.account_id
                        AND candidate_item.remote_id = candidate.remote_id
                        AND candidate_item.remote_parent_id = candidate.remote_parent_id
                    INNER JOIN task_bindings AS candidate_binding
                        ON candidate_binding.provider_item_id = candidate_item.id
                    WHERE candidate_binding.event_task_id = binding.event_task_id
                    ORDER BY candidate.updated_at DESC, candidate.rowid DESC
                    LIMIT 1
                  );

                DROP TABLE provider_pending_operations_v9;

                CREATE INDEX provider_pending_operations_account
                    ON provider_pending_operations(account_id, updated_at);
                CREATE INDEX provider_pending_operations_task
                    ON provider_pending_operations(event_task_id);

                CREATE TABLE task_provider_preferences (
                    event_task_id TEXT PRIMARY KEY NOT NULL
                        REFERENCES event_tasks(id) ON DELETE CASCADE,
                    link_mode TEXT NOT NULL
                        CHECK (link_mode IN ('local_only')),
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
            """)
        }
        migrator.registerMigration("v11_local_task_planning") { db in
            try db.execute(sql: """
                CREATE TABLE task_planning_metadata (
                    task_kind TEXT NOT NULL
                        CHECK (task_kind IN ('event', 'personal')),
                    task_id TEXT NOT NULL
                        CHECK (length(trim(task_id)) > 0),
                    priority INTEGER NOT NULL DEFAULT 0
                        CHECK (priority BETWEEN 0 AND 3),
                    important BOOLEAN NOT NULL DEFAULT 0
                        CHECK (important IN (0, 1)),
                    repeat_frequency TEXT NOT NULL DEFAULT 'none'
                        CHECK (repeat_frequency IN (
                            'none', 'daily', 'weekly', 'monthly', 'yearly'
                        )),
                    repeat_interval INTEGER NOT NULL DEFAULT 1
                        CHECK (repeat_interval BETWEEN 1 AND 365),
                    estimated_minutes INTEGER
                        CHECK (estimated_minutes IS NULL
                            OR estimated_minutes BETWEEN 1 AND 525600),
                    actual_seconds INTEGER NOT NULL DEFAULT 0
                        CHECK (actual_seconds >= 0),
                    started_at TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    PRIMARY KEY (task_kind, task_id),
                    CHECK (repeat_frequency != 'none' OR repeat_interval = 1)
                );
                CREATE INDEX task_planning_priority
                    ON task_planning_metadata(important DESC, priority DESC);
                CREATE INDEX task_planning_running
                    ON task_planning_metadata(started_at)
                    WHERE started_at IS NOT NULL;

                CREATE TABLE task_checklist_items (
                    id TEXT PRIMARY KEY NOT NULL,
                    task_kind TEXT NOT NULL
                        CHECK (task_kind IN ('event', 'personal')),
                    parent_task_id TEXT NOT NULL
                        CHECK (length(trim(parent_task_id)) > 0),
                    title TEXT NOT NULL
                        CHECK (length(trim(title)) BETWEEN 1 AND 500),
                    completed BOOLEAN NOT NULL DEFAULT 0
                        CHECK (completed IN (0, 1)),
                    sort_order INTEGER NOT NULL DEFAULT 0
                        CHECK (sort_order >= 0),
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE INDEX task_checklist_parent_order
                    ON task_checklist_items(
                        task_kind, parent_task_id, sort_order, created_at, id
                    );

                CREATE TRIGGER task_planning_event_cleanup
                AFTER DELETE ON event_tasks
                BEGIN
                    DELETE FROM task_checklist_items
                    WHERE task_kind = 'event' AND parent_task_id = OLD.id;
                    DELETE FROM task_planning_metadata
                    WHERE task_kind = 'event' AND task_id = OLD.id;
                END;

                CREATE TRIGGER task_planning_personal_cleanup
                AFTER DELETE ON personal_tasks
                BEGIN
                    DELETE FROM task_checklist_items
                    WHERE task_kind = 'personal' AND parent_task_id = OLD.id;
                    DELETE FROM task_planning_metadata
                    WHERE task_kind = 'personal' AND task_id = OLD.id;
                END;
            """)
        }
        return migrator
    }
}
