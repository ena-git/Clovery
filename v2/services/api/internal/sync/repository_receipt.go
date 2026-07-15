package sync

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"
)

func loadOperationReceipt(
	ctx context.Context,
	transaction *sql.Tx,
	operationID string,
	vaultID string,
) ([]byte, []byte, bool, error) {
	var requestHash []byte
	var result []byte
	err := transaction.QueryRowContext(
		ctx,
		"SELECT request_hash, result FROM sync_operations WHERE operation_id = $1 AND vault_id = $2",
		operationID,
		vaultID,
	).Scan(&requestHash, &result)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil, false, nil
	}
	if err != nil {
		return nil, nil, false, fmt.Errorf("load sync operation receipt: %w", err)
	}
	return requestHash, result, true, nil
}

func storeOperationReceipt(
	ctx context.Context,
	transaction *sql.Tx,
	vaultID string,
	operationID string,
	requestHash []byte,
	decision Decision,
	now time.Time,
) error {
	result, err := json.Marshal(decision)
	if err != nil {
		return fmt.Errorf("encode sync operation receipt: %w", err)
	}
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO sync_operations (operation_id, vault_id, request_hash, result, created_at)
		 VALUES ($1, $2, $3, $4, $5)`,
		operationID,
		vaultID,
		requestHash,
		result,
		now,
	); err != nil {
		return fmt.Errorf("store sync operation receipt: %w", err)
	}
	return nil
}
