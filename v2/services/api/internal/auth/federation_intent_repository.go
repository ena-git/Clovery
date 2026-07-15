package auth

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

func (store *PostgresFederationStore) CreateBindingIntent(
	ctx context.Context,
	intent BindingIntentRecord,
) error {
	_, err := store.database.ExecContext(
		ctx,
		`INSERT INTO federation_intents (
			id, purpose, account_id, session_id, provider, nonce_hash, expires_at
		) VALUES ($1, 'binding', $2, $3, $4, $5, $6)`,
		intent.ID,
		intent.AccountID,
		intent.SessionID,
		intent.Provider,
		intent.NonceHash,
		intent.ExpiresAt,
	)
	if err != nil {
		return fmt.Errorf("insert federation binding intent: %w", err)
	}
	return nil
}

func (store *PostgresFederationStore) CreateLoginIntent(
	ctx context.Context,
	intent FederatedLoginIntentRecord,
) error {
	_, err := store.database.ExecContext(
		ctx,
		`INSERT INTO federation_intents (id, purpose, provider, nonce_hash, expires_at)
		 VALUES ($1, 'login', $2, $3, $4)`,
		intent.ID,
		intent.Provider,
		intent.NonceHash,
		intent.ExpiresAt,
	)
	if err != nil {
		return fmt.Errorf("insert federated login intent: %w", err)
	}
	return nil
}

func (store *PostgresFederationStore) ConsumeBindingIntent(
	ctx context.Context,
	intent ConsumeFederatedBindingIntent,
) error {
	var intentID string
	err := store.database.QueryRowContext(
		ctx,
		`UPDATE federation_intents
		 SET used_at = $6
		 WHERE id = $1
		   AND purpose = 'binding'
		   AND account_id = $2
		   AND session_id = $3
		   AND provider = $4
		   AND nonce_hash = $5
		   AND used_at IS NULL
		   AND expires_at > $6
		 RETURNING id`,
		intent.ID,
		intent.AccountID,
		intent.SessionID,
		intent.Provider,
		intent.NonceHash,
		intent.UsedAt,
	).Scan(&intentID)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrFederatedAuthentication
	}
	if err != nil {
		return fmt.Errorf("consume federation binding intent: %w", err)
	}
	return nil
}

func (store *PostgresFederationStore) ConsumeLoginIntent(
	ctx context.Context,
	intent ConsumeFederatedLoginIntent,
) error {
	var intentID string
	err := store.database.QueryRowContext(
		ctx,
		`UPDATE federation_intents
		 SET used_at = $4
		 WHERE id = $1
		   AND purpose = 'login'
		   AND provider = $2
		   AND nonce_hash = $3
		   AND used_at IS NULL
		   AND expires_at > $4
		 RETURNING id`,
		intent.ID,
		intent.Provider,
		intent.NonceHash,
		intent.UsedAt,
	).Scan(&intentID)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrFederatedAuthentication
	}
	if err != nil {
		return fmt.Errorf("consume federated login intent: %w", err)
	}
	return nil
}
