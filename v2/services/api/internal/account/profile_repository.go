package account

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

func (repository *Repository) GetProfile(ctx context.Context, accountID string) (Profile, error) {
	var profile Profile
	err := repository.database.QueryRowContext(
		ctx,
		`SELECT a.id, login.normalized_id, a.status, a.created_at,
		 EXISTS (SELECT 1 FROM password_credentials WHERE account_id = a.id),
		 (SELECT COUNT(*) FROM passkeys WHERE account_id = a.id),
		 (SELECT COUNT(*) FROM recovery_codes WHERE account_id = a.id AND used_at IS NULL)
		 FROM clovery_accounts a
		 JOIN account_login_ids login ON login.account_id = a.id AND login.status = 'active'
		 WHERE a.id = $1`,
		accountID,
	).Scan(
		&profile.AccountID,
		&profile.CloveryID,
		&profile.Status,
		&profile.CreatedAt,
		&profile.HasPassword,
		&profile.PasskeyCount,
		&profile.RecoveryCodeCount,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return Profile{}, ErrAccountNotFound
	}
	if err != nil {
		return Profile{}, fmt.Errorf("load account profile: %w", err)
	}
	bindings, err := repository.listBindings(ctx, accountID)
	if err != nil {
		return Profile{}, err
	}
	profile.Bindings = bindings
	return profile, nil
}

func (repository *Repository) listBindings(ctx context.Context, accountID string) ([]Binding, error) {
	rows, err := repository.database.QueryContext(
		ctx,
		`SELECT provider, issuer, created_at FROM external_identities
		 WHERE account_id = $1 ORDER BY provider`,
		accountID,
	)
	if err != nil {
		return nil, fmt.Errorf("list account bindings: %w", err)
	}
	defer rows.Close()

	var bindings []Binding
	for rows.Next() {
		var binding Binding
		if err := rows.Scan(&binding.Provider, &binding.Issuer, &binding.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan account binding: %w", err)
		}
		bindings = append(bindings, binding)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate account bindings: %w", err)
	}
	return bindings, nil
}
