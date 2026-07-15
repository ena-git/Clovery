package auth

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/google/uuid"
)

func (store *PostgresPasskeyStore) UpdateCredential(
	ctx context.Context,
	accountID string,
	credential PasskeyCredential,
) error {
	if len(credential.ID) == 0 || len(credential.PublicKey) == 0 || len(credential.Record) == 0 {
		return ErrPasskeyAuthentication
	}
	encrypted, err := store.cipher.Encrypt(accountID, credential.ID, credential.Record)
	if err != nil {
		return err
	}
	var passkeyID string
	err = store.database.QueryRowContext(
		ctx,
		`UPDATE passkeys
		 SET sign_counter = $4,
		     credential_key_version = $5,
		     credential_record_nonce = $6,
		     credential_record_ciphertext = $7
		 WHERE account_id = $1
		   AND credential_id = $2
		   AND public_key = $3
		 RETURNING id`,
		accountID,
		credential.ID,
		credential.PublicKey,
		credential.SignCount,
		encrypted.KeyVersion,
		encrypted.Nonce,
		encrypted.Ciphertext,
	).Scan(&passkeyID)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrPasskeyAuthentication
	}
	if err != nil {
		return fmt.Errorf("update passkey credential state: %w", err)
	}
	return nil
}

func (store *PostgresPasskeyStore) SaveCredential(
	ctx context.Context,
	accountID string,
	credential PasskeyCredential,
) error {
	if len(credential.ID) == 0 || len(credential.PublicKey) == 0 || len(credential.Record) == 0 {
		return ErrPasskeyAuthentication
	}
	encrypted, err := store.cipher.Encrypt(accountID, credential.ID, credential.Record)
	if err != nil {
		return err
	}
	credentialID, err := randomUUID(store.random)
	if err != nil {
		return fmt.Errorf("generate passkey record ID: %w", err)
	}
	deviceMetadata := credential.DeviceMetadata
	if len(deviceMetadata) == 0 {
		deviceMetadata = json.RawMessage(`{}`)
	}

	transaction, err := store.database.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin passkey credential transaction: %w", err)
	}
	defer func() { _ = transaction.Rollback() }()
	var lockedAccountID string
	if err := transaction.QueryRowContext(
		ctx,
		"SELECT id FROM clovery_accounts WHERE id = $1 FOR UPDATE",
		accountID,
	).Scan(&lockedAccountID); err != nil {
		return fmt.Errorf("lock account for passkey credential: %w", err)
	}
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO passkeys (
			id, account_id, credential_id, public_key, sign_counter, device_metadata,
			credential_key_version, credential_record_nonce, credential_record_ciphertext
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
		credentialID,
		accountID,
		credential.ID,
		credential.PublicKey,
		credential.SignCount,
		[]byte(deviceMetadata),
		encrypted.KeyVersion,
		encrypted.Nonce,
		encrypted.Ciphertext,
	); err != nil {
		return fmt.Errorf("insert passkey credential: %w", err)
	}
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO audit_events (id, account_id, event_type, payload)
		 VALUES ($1, $2, 'passkey_registered', jsonb_build_object('passkey_id', $3::text))`,
		uuid.NewString(),
		accountID,
		credentialID,
	); err != nil {
		return fmt.Errorf("audit passkey registration: %w", err)
	}
	if err := transaction.Commit(); err != nil {
		return fmt.Errorf("commit passkey credential: %w", err)
	}
	return nil
}
