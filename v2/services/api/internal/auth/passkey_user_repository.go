package auth

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"io"
)

func (store *PostgresPasskeyStore) FindUserByCredential(
	ctx context.Context,
	credentialID []byte,
	userHandle []byte,
) (PasskeyUser, error) {
	var accountID string
	err := store.database.QueryRowContext(
		ctx,
		`SELECT passkeys.account_id
		 FROM passkeys
		 JOIN webauthn_users ON webauthn_users.account_id = passkeys.account_id
		 WHERE passkeys.credential_id = $1
		   AND webauthn_users.user_handle = $2`,
		credentialID,
		userHandle,
	).Scan(&accountID)
	if errors.Is(err, sql.ErrNoRows) {
		return PasskeyUser{}, ErrPasskeyAuthentication
	}
	if err != nil {
		return PasskeyUser{}, fmt.Errorf("find passkey user by credential: %w", err)
	}
	return store.EnsureUser(ctx, accountID)
}

func (store *PostgresPasskeyStore) EnsureUser(
	ctx context.Context,
	accountID string,
) (PasskeyUser, error) {
	transaction, err := store.database.BeginTx(ctx, nil)
	if err != nil {
		return PasskeyUser{}, fmt.Errorf("begin passkey user transaction: %w", err)
	}
	defer func() { _ = transaction.Rollback() }()

	user := PasskeyUser{AccountID: accountID}
	if err := transaction.QueryRowContext(
		ctx,
		`SELECT account_login_ids.normalized_id, vaults.id
		 FROM clovery_accounts
		 JOIN account_login_ids ON account_login_ids.account_id = clovery_accounts.id
		 JOIN vaults ON vaults.owner_account_id = clovery_accounts.id
		 WHERE clovery_accounts.id = $1
		   AND account_login_ids.status = 'active'
		   AND vaults.status = 'active'
		 FOR UPDATE OF clovery_accounts`,
		accountID,
	).Scan(&user.Name, &user.VaultID); err != nil {
		return PasskeyUser{}, fmt.Errorf("load passkey account: %w", err)
	}

	err = transaction.QueryRowContext(
		ctx,
		"SELECT user_handle FROM webauthn_users WHERE account_id = $1",
		accountID,
	).Scan(&user.Handle)
	if errors.Is(err, sql.ErrNoRows) {
		user.Handle = make([]byte, 32)
		if _, err := io.ReadFull(store.random, user.Handle); err != nil {
			return PasskeyUser{}, fmt.Errorf("generate WebAuthn user handle: %w", err)
		}
		if _, err := transaction.ExecContext(
			ctx,
			"INSERT INTO webauthn_users (account_id, user_handle) VALUES ($1, $2)",
			accountID,
			user.Handle,
		); err != nil {
			return PasskeyUser{}, fmt.Errorf("insert WebAuthn user handle: %w", err)
		}
	} else if err != nil {
		return PasskeyUser{}, fmt.Errorf("load WebAuthn user handle: %w", err)
	}

	records, err := store.loadCredentialRecords(ctx, transaction, accountID)
	if err != nil {
		return PasskeyUser{}, err
	}
	user.CredentialRecords = records
	if err := transaction.Commit(); err != nil {
		return PasskeyUser{}, fmt.Errorf("commit passkey user transaction: %w", err)
	}
	return user, nil
}

func (store *PostgresPasskeyStore) loadCredentialRecords(
	ctx context.Context,
	transaction *sql.Tx,
	accountID string,
) ([][]byte, error) {
	rows, err := transaction.QueryContext(
		ctx,
		`SELECT credential_id, credential_key_version,
		        credential_record_nonce, credential_record_ciphertext
		 FROM passkeys
		 WHERE account_id = $1
		 ORDER BY created_at`,
		accountID,
	)
	if err != nil {
		return nil, fmt.Errorf("load passkey credentials: %w", err)
	}
	defer rows.Close()

	var records [][]byte
	for rows.Next() {
		var credentialID []byte
		var encrypted EncryptedPasskeyCredential
		if err := rows.Scan(
			&credentialID,
			&encrypted.KeyVersion,
			&encrypted.Nonce,
			&encrypted.Ciphertext,
		); err != nil {
			return nil, fmt.Errorf("scan passkey credential: %w", err)
		}
		record, err := store.cipher.Decrypt(accountID, credentialID, encrypted)
		if err != nil {
			return nil, err
		}
		records = append(records, record)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate passkey credentials: %w", err)
	}
	return records, nil
}
