package auth

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

func (store *PostgresPasskeyStore) CreateChallenge(
	ctx context.Context,
	challenge PasskeyChallengeRecord,
) error {
	_, err := store.database.ExecContext(
		ctx,
		`INSERT INTO passkey_challenges (
			id, purpose, account_id, session_id, session_data, expires_at
		) VALUES ($1, $2, NULLIF($3, '')::uuid, NULLIF($4, '')::uuid, $5, $6)`,
		challenge.ID,
		challenge.Purpose,
		challenge.AccountID,
		challenge.SessionID,
		challenge.SessionData,
		challenge.ExpiresAt,
	)
	if err != nil {
		return fmt.Errorf("insert passkey challenge: %w", err)
	}
	return nil
}

func (store *PostgresPasskeyStore) ConsumeChallenge(
	ctx context.Context,
	challenge ConsumePasskeyChallenge,
) ([]byte, error) {
	var sessionData []byte
	err := store.database.QueryRowContext(
		ctx,
		`UPDATE passkey_challenges
		 SET used_at = $5
		 WHERE id = $1
		   AND purpose = $2
		   AND (($3 = '' AND account_id IS NULL) OR account_id::text = $3)
		   AND (($4 = '' AND session_id IS NULL) OR session_id::text = $4)
		   AND used_at IS NULL
		   AND expires_at > $5
		 RETURNING session_data`,
		challenge.ID,
		challenge.Purpose,
		challenge.AccountID,
		challenge.SessionID,
		challenge.UsedAt,
	).Scan(&sessionData)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrPasskeyAuthentication
	}
	if err != nil {
		return nil, fmt.Errorf("consume passkey challenge: %w", err)
	}
	return sessionData, nil
}
