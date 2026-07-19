package identityclaim

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

type IssueRepository interface {
	Issue(ctx context.Context, claim StoredClaim) error
}

type RegistrationTransaction interface {
	QueryRowContext(ctx context.Context, query string, arguments ...any) *sql.Row
	ExecContext(ctx context.Context, query string, arguments ...any) (sql.Result, error)
}

type PostgresRepository struct {
	database *sql.DB
}

func NewPostgresRepository(database *sql.DB) *PostgresRepository {
	return &PostgresRepository{database: database}
}

func (repository *PostgresRepository) Issue(ctx context.Context, claim StoredClaim) error {
	_, err := repository.database.ExecContext(
		ctx,
		`INSERT INTO identity_claims (
			id, token_sha256, provider, issuer, subject, login_intent_id, expires_at, created_at
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
		claim.ID,
		claim.TokenSHA256,
		claim.Identity.Provider,
		claim.Identity.Issuer,
		claim.Identity.Subject,
		claim.Identity.IntentID,
		claim.ExpiresAt,
		claim.CreatedAt,
	)
	if err != nil {
		return fmt.Errorf("insert identity claim: %w", err)
	}
	return nil
}

func (repository *PostgresRepository) LockForRegistration(
	ctx context.Context,
	transaction RegistrationTransaction,
	rawToken string,
) (*LockedClaim, error) {
	var claim LockedClaim
	var consumedAt sql.NullTime
	var consumedByAccountID sql.NullString
	var registrationRequestID sql.NullString
	err := transaction.QueryRowContext(
		ctx,
		`SELECT claim.id::text,
		        claim.provider,
		        claim.issuer,
		        claim.subject,
		        claim.login_intent_id::text,
		        claim.expires_at,
		        claim.consumed_at,
		        claim.consumed_by_account_id::text,
		        claim.registration_request_id::text
		 FROM identity_claims AS claim
		 WHERE claim.token_sha256 = $1
		 FOR UPDATE OF claim`,
		tokenSHA256(rawToken),
	).Scan(
		&claim.ID,
		&claim.Identity.Provider,
		&claim.Identity.Issuer,
		&claim.Identity.Subject,
		&claim.Identity.IntentID,
		&claim.ExpiresAt,
		&consumedAt,
		&consumedByAccountID,
		&registrationRequestID,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrInvalidClaim
	}
	if err != nil {
		return nil, fmt.Errorf("lock identity claim: %w", err)
	}
	if consumedAt.Valid {
		claim.ConsumedAt = &consumedAt.Time
	}
	if consumedByAccountID.Valid {
		claim.ConsumedByAccountID = &consumedByAccountID.String
	}
	if registrationRequestID.Valid {
		claim.RegistrationRequestID = &registrationRequestID.String
	}
	if consumedByAccountID.Valid {
		var existingVaultID string
		err := transaction.QueryRowContext(
			ctx,
			`SELECT vault.id::text
			 FROM clovery_accounts AS account
			 JOIN vaults AS vault
			   ON vault.owner_account_id = account.id
			 WHERE account.id = $1`,
			consumedByAccountID.String,
		).Scan(&existingVaultID)
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrInvalidClaim
		}
		if err != nil {
			return nil, fmt.Errorf("load consumed identity claim vault: %w", err)
		}
		claim.ExistingVaultID = &existingVaultID
	}
	return &claim, nil
}

func (repository *PostgresRepository) MarkConsumed(
	ctx context.Context,
	transaction RegistrationTransaction,
	claimID string,
	consumedAt time.Time,
	accountID string,
	registrationRequestID string,
) error {
	result, err := transaction.ExecContext(
		ctx,
		`UPDATE identity_claims
		 SET consumed_at = $2,
		     consumed_by_account_id = $3,
		     registration_request_id = $4
		 WHERE id = $1
		   AND consumed_at IS NULL`,
		claimID,
		consumedAt,
		accountID,
		registrationRequestID,
	)
	if err != nil {
		return fmt.Errorf("mark identity claim consumed: %w", err)
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("read identity claim consumption result: %w", err)
	}
	if rowsAffected != 1 {
		return ErrConsumedClaim
	}
	return nil
}
