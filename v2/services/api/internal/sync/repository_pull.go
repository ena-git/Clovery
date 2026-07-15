package sync

import (
	"context"
	"fmt"
)

func (repository *PostgresRepository) ListChanges(
	ctx context.Context,
	vaultID string,
	cursor int64,
	limit int,
) ([]Change, error) {
	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT cursor, entity_type, entity_id, revision, operation_id, payload, deleted, changed_at
		 FROM sync_changes WHERE vault_id = $1 AND cursor > $2
		 ORDER BY cursor LIMIT $3`,
		vaultID,
		cursor,
		limit,
	)
	if err != nil {
		return nil, fmt.Errorf("list sync changes: %w", err)
	}
	defer rows.Close()

	var changes []Change
	for rows.Next() {
		var change Change
		if err := rows.Scan(
			&change.Cursor,
			&change.EntityType,
			&change.EntityID,
			&change.Revision,
			&change.OperationID,
			&change.Payload,
			&change.Deleted,
			&change.ChangedAt,
		); err != nil {
			return nil, fmt.Errorf("scan sync change: %w", err)
		}
		changes = append(changes, change)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate sync changes: %w", err)
	}
	return changes, nil
}
