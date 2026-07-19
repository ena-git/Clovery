package account

import (
	"context"
	"fmt"

	"github.com/clovery/clovery/services/api/internal/identityclaim"
)

type CreateClaimedAccountParams struct {
	AccountID             string
	VaultID               string
	LoginID               string
	PasswordHash          string
	IdentityClaimToken    identityclaim.RegistrationToken
	RegistrationRequestID string
	SourceKind            string
}

type CreateClaimedAccountResult struct {
	AccountID string
	VaultID   string
}

func (repository *Repository) CreateClaimedAccount(
	ctx context.Context,
	params CreateClaimedAccountParams,
	claimRepository *identityclaim.PostgresRepository,
	claims *identityclaim.Service,
) (CreateClaimedAccountResult, error) {
	if claimRepository == nil {
		return CreateClaimedAccountResult{}, fmt.Errorf("account: nil identity claim repository")
	}
	if claims == nil {
		return CreateClaimedAccountResult{}, fmt.Errorf("account: nil identity claim service")
	}
	normalizedID, err := NormalizeLoginID(params.LoginID)
	if err != nil {
		return CreateClaimedAccountResult{}, err
	}
	transaction, err := repository.database.BeginTx(ctx, nil)
	if err != nil {
		return CreateClaimedAccountResult{}, fmt.Errorf("begin claimed account transaction: %w", err)
	}
	defer func() { _ = transaction.Rollback() }()

	lockedClaim, err := claimRepository.LockForRegistration(ctx, transaction, params.IdentityClaimToken)
	if err != nil {
		return CreateClaimedAccountResult{}, err
	}
	resolution, err := claims.ResolveForRegistration(lockedClaim, params.RegistrationRequestID)
	if err != nil {
		return CreateClaimedAccountResult{}, err
	}
	if resolution.Existing != nil {
		if err := transaction.Commit(); err != nil {
			return CreateClaimedAccountResult{}, fmt.Errorf("commit claimed account replay: %w", err)
		}
		return CreateClaimedAccountResult{
			AccountID: resolution.Existing.AccountID,
			VaultID:   resolution.Existing.VaultID,
		}, nil
	}
	if resolution.PendingConsumption == nil {
		return CreateClaimedAccountResult{}, identityclaim.ErrInvalidClaim
	}

	identity := resolution.Identity
	var identityAlreadyBound bool
	if err := transaction.QueryRowContext(
		ctx,
		`SELECT EXISTS (
			SELECT 1 FROM external_identities
			WHERE provider = $1 AND issuer = $2 AND subject = $3
		)`,
		identity.Provider,
		identity.Issuer,
		identity.Subject,
	).Scan(&identityAlreadyBound); err != nil {
		return CreateClaimedAccountResult{}, fmt.Errorf("check claimed external identity: %w", err)
	}
	if identityAlreadyBound {
		return CreateClaimedAccountResult{}, ErrIdentityAlreadyBound
	}
	if err := insertAccountRows(ctx, transaction, CreateAccountParams{
		AccountID:    params.AccountID,
		VaultID:      params.VaultID,
		LoginID:      params.LoginID,
		PasswordHash: params.PasswordHash,
	}, normalizedID); err != nil {
		return CreateClaimedAccountResult{}, err
	}
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO external_identities (account_id, provider, issuer, subject)
		 VALUES ($1, $2, $3, $4)`,
		params.AccountID,
		identity.Provider,
		identity.Issuer,
		identity.Subject,
	); err != nil {
		if isConstraint(err, "external_identities_provider_subject_key") ||
			isConstraint(err, "external_identities_account_provider_key") {
			return CreateClaimedAccountResult{}, ErrIdentityAlreadyBound
		}
		return CreateClaimedAccountResult{}, fmt.Errorf("insert claimed external identity: %w", err)
	}
	migrationState := "pending"
	if params.SourceKind == "new_install" {
		migrationState = "complete"
	}
	if _, err := transaction.ExecContext(
		ctx,
		`INSERT INTO account_bootstrap_jobs (
			account_id, vault_id, source_kind,
			identity_state, migration_state, entitlement_state, vault_state
		) VALUES ($1, $2, $3, 'complete', $4, 'pending', 'pending')`,
		params.AccountID,
		params.VaultID,
		params.SourceKind,
		migrationState,
	); err != nil {
		return CreateClaimedAccountResult{}, fmt.Errorf("insert account bootstrap job: %w", err)
	}
	if err := claimRepository.MarkConsumed(
		ctx,
		transaction,
		resolution.PendingConsumption,
		params.AccountID,
		params.RegistrationRequestID,
	); err != nil {
		return CreateClaimedAccountResult{}, err
	}
	if err := transaction.Commit(); err != nil {
		return CreateClaimedAccountResult{}, fmt.Errorf("commit claimed account transaction: %w", err)
	}
	return CreateClaimedAccountResult{AccountID: params.AccountID, VaultID: params.VaultID}, nil
}
