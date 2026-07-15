package auth

import (
	"context"
)

func (service *LoginService) lookupPasswordCredential(
	ctx context.Context,
	normalizedID string,
) (LoginResult, string, error) {
	result := LoginResult{}
	var encodedHash string
	err := service.database.QueryRowContext(
		ctx,
		`SELECT account_login_ids.account_id, vaults.id, password_credentials.password_hash
		 FROM account_login_ids
		 JOIN vaults ON vaults.owner_account_id = account_login_ids.account_id
		 JOIN password_credentials ON password_credentials.account_id = account_login_ids.account_id
		 WHERE account_login_ids.normalized_id = $1
		   AND account_login_ids.status = 'active'
		   AND vaults.status = 'active'`,
		normalizedID,
	).Scan(&result.AccountID, &result.VaultID, &encodedHash)
	return result, encodedHash, err
}
