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
        return migrator
    }
}
