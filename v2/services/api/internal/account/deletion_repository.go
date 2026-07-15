package account

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"github.com/google/uuid"
)

var ErrAccountUnavailable = errors.New("account is unavailable")

func (repository *Repository) CreateDeletionRequest(
	ctx context.Context,
	params CreateDeletionRequestParams,
) (DeletionRequest, error) {
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return DeletionRequest{}, fmt.Errorf("begin account deletion request: %w", err)
	}
	defer func() { _ = transaction.Rollback() }()

	var accountStatus string
	if err := transaction.QueryRowContext(
		ctx,
		"SELECT status FROM clovery_accounts WHERE id = $1 FOR UPDATE",
		params.AccountID,
	).Scan(&accountStatus); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return DeletionRequest{}, ErrAccountNotFound
		}
		return DeletionRequest{}, fmt.Errorf("lock account deletion state: %w", err)
	}
	if accountStatus == "deletion_requested" {
		return repository.commitExistingDeletionRequest(ctx, transaction, params.AccountID)
	}
	if accountStatus != "active" {
		return DeletionRequest{}, ErrAccountUnavailable
	}

	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO account_deletion_requests (id, account_id, status, requested_at, scheduled_for)
		 VALUES ($1, $2, 'pending', $3, $4)`,
		params.ID,
		params.AccountID,
		params.RequestedAt,
		params.ScheduledFor,
	); err != nil {
		return DeletionRequest{}, fmt.Errorf("insert account deletion request: %w", err)
	}
	if err := applyDeletionLock(ctx, transaction, params); err != nil {
		return DeletionRequest{}, err
	}
	if err := transaction.Commit(); err != nil {
		return DeletionRequest{}, fmt.Errorf("commit account deletion request: %w", err)
	}
	return DeletionRequest{
		ID:           params.ID,
		AccountID:    params.AccountID,
		Status:       "pending",
		RequestedAt:  params.RequestedAt,
		ScheduledFor: params.ScheduledFor,
	}, nil
}

func applyDeletionLock(
	ctx context.Context,
	transaction *sql.Tx,
	params CreateDeletionRequestParams,
) error {
	statements := []struct {
		query string
		args  []any
	}{
		{`UPDATE clovery_accounts SET status = 'deletion_requested', deletion_requested_at = $2 WHERE id = $1`, []any{params.AccountID, params.RequestedAt}},
		{`UPDATE vaults SET status = 'locked' WHERE owner_account_id = $1`, []any{params.AccountID}},
		{`UPDATE sessions SET revoked_at = COALESCE(revoked_at, $2)
		  WHERE device_id IN (SELECT id FROM devices WHERE account_id = $1)`, []any{params.AccountID, params.RequestedAt}},
		{`INSERT INTO audit_events (id, account_id, event_type, payload, created_at)
		  VALUES ($1, $2, 'account_deletion_requested',
		  jsonb_build_object('request_id', $3::uuid, 'scheduled_for', $4::timestamptz), $5)`, []any{
			uuid.NewString(), params.AccountID, params.ID, params.ScheduledFor, params.RequestedAt,
		}},
	}
	for _, statement := range statements {
		if _, err := transaction.ExecContext(ctx, statement.query, statement.args...); err != nil {
			return fmt.Errorf("apply account deletion lock: %w", err)
		}
	}
	return nil
}

func (repository *Repository) commitExistingDeletionRequest(
	ctx context.Context,
	transaction *sql.Tx,
	accountID string,
) (DeletionRequest, error) {
	var request DeletionRequest
	err := transaction.QueryRowContext(
		ctx,
		`SELECT id, account_id, status, requested_at, scheduled_for
		 FROM account_deletion_requests WHERE account_id = $1 AND status = 'pending'`,
		accountID,
	).Scan(&request.ID, &request.AccountID, &request.Status, &request.RequestedAt, &request.ScheduledFor)
	if err != nil {
		return DeletionRequest{}, fmt.Errorf("load pending account deletion request: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return DeletionRequest{}, fmt.Errorf("commit pending account deletion lookup: %w", err)
	}
	return request, nil
}
