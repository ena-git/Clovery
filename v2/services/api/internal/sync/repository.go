package sync

import (
	"context"
	"crypto/hmac"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"
)

var ErrOperationReplayMismatch = errors.New("operation ID was reused with different content")

type PostgresRepository struct {
	database *sql.DB
}

func NewPostgresRepository(database *sql.DB) *PostgresRepository {
	return &PostgresRepository{database: database}
}

func (repository *PostgresRepository) Apply(
	ctx context.Context,
	vaultID string,
	operation Operation,
	now time.Time,
) (Decision, error) {
	fingerprint, err := OperationFingerprint(operation)
	if err != nil {
		return Decision{}, err
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return Decision{}, fmt.Errorf("begin sync operation: %w", err)
	}
	defer func() { _ = transaction.Rollback() }()
	if _, err := transaction.ExecContext(
		ctx,
		"SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
		operation.OperationID,
	); err != nil {
		return Decision{}, fmt.Errorf("lock sync operation: %w", err)
	}

	storedHash, storedResult, found, err := loadOperationReceipt(ctx, transaction, operation.OperationID, vaultID)
	if err != nil {
		return Decision{}, err
	}
	if found {
		if !hmac.Equal(storedHash, fingerprint) {
			return Decision{}, ErrOperationReplayMismatch
		}
		var result Decision
		if err := json.Unmarshal(storedResult, &result); err != nil {
			return Decision{}, fmt.Errorf("decode sync operation receipt: %w", err)
		}
		if err := transaction.Commit(); err != nil {
			return Decision{}, fmt.Errorf("commit sync replay lookup: %w", err)
		}
		return result, nil
	}
	entryLockKey := "journal_entry:" + vaultID + ":" + operation.EntryID
	if _, err := transaction.ExecContext(
		ctx,
		"SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
		entryLockKey,
	); err != nil {
		return Decision{}, fmt.Errorf("lock journal entry: %w", err)
	}

	current, err := loadCurrentEntry(ctx, transaction, vaultID, operation.EntryID)
	if err != nil {
		return Decision{}, err
	}
	decision, err := DecideOperation(current, operation, now)
	if err != nil {
		return Decision{}, err
	}
	if decision.Status == StatusConflict {
		err = persistConflict(ctx, transaction, vaultID, operation, decision, now)
	} else {
		err = persistAppliedOperation(ctx, transaction, vaultID, operation, &decision, now)
	}
	if err != nil {
		return Decision{}, err
	}
	if err := storeOperationReceipt(ctx, transaction, vaultID, operation.OperationID, fingerprint, decision, now); err != nil {
		return Decision{}, err
	}
	if err := transaction.Commit(); err != nil {
		return Decision{}, fmt.Errorf("commit sync operation: %w", err)
	}
	return decision, nil
}
