package account

import (
	"context"
	"fmt"
	"strings"
)

type ExternalIdentity struct {
	Provider string
	Issuer   string
	Subject  string
}

func (repository *Repository) BindExternalIdentity(
	ctx context.Context,
	accountID string,
	identity ExternalIdentity,
) error {
	provider := strings.TrimSpace(identity.Provider)
	issuer := strings.TrimSpace(identity.Issuer)
	subject := strings.TrimSpace(identity.Subject)
	if provider == "" || issuer == "" || subject == "" {
		return fmt.Errorf("external identity fields are required")
	}
	_, err := repository.database.ExecContext(
		ctx,
		`INSERT INTO external_identities (account_id, provider, issuer, subject)
		 VALUES ($1, $2, $3, $4)`,
		accountID,
		provider,
		issuer,
		subject,
	)
	if isConstraint(err, "external_identities_provider_subject_key") ||
		isConstraint(err, "external_identities_account_provider_key") {
		return ErrIdentityAlreadyBound
	}
	if err != nil {
		return fmt.Errorf("insert external identity: %w", err)
	}
	return nil
}
