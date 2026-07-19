package identityclaim

import (
	"context"
	"crypto/rand"
	"fmt"
	"io"
	"time"

	"github.com/google/uuid"
)

const claimLifetime = 10 * time.Minute

type Service struct {
	repository   IssueRepository
	randomSource io.Reader
	now          func() time.Time
	newID        func() string
}

func NewService(repository IssueRepository) *Service {
	return &Service{
		repository:   repository,
		randomSource: rand.Reader,
		now:          func() time.Time { return time.Now().UTC() },
		newID:        uuid.NewString,
	}
}

func (service *Service) Issue(ctx context.Context, identity Identity) (IssuedClaim, error) {
	if !validIdentity(identity) {
		return IssuedClaim{}, ErrInvalidIdentity
	}
	rawToken, digest, err := newToken(service.randomSource)
	if err != nil {
		return IssuedClaim{}, err
	}
	issuedAt := service.now()
	claim := StoredClaim{
		ID:          service.newID(),
		TokenSHA256: digest,
		Identity:    identity,
		ExpiresAt:   issuedAt.Add(claimLifetime),
		CreatedAt:   issuedAt,
	}
	if err := service.repository.Issue(ctx, claim); err != nil {
		return IssuedClaim{}, fmt.Errorf("issue identity claim: %w", err)
	}
	return IssuedClaim{
		Token:     rawToken,
		Provider:  identity.Provider,
		ExpiresIn: claimLifetime,
	}, nil
}

func (service *Service) ResolveForRegistration(
	claim *LockedClaim,
	registrationRequestID string,
) (RegistrationResolution, error) {
	if claim == nil || claim.ID == "" || claim.ExpiresAt.IsZero() {
		return RegistrationResolution{}, ErrInvalidClaim
	}
	if claim.ConsumedAt == nil {
		if claim.ConsumedByAccountID != nil || claim.RegistrationRequestID != nil || claim.ExistingVaultID != nil {
			return RegistrationResolution{}, ErrInvalidClaim
		}
		if !claim.ExpiresAt.After(service.now()) {
			return RegistrationResolution{}, ErrExpiredClaim
		}
		return RegistrationResolution{Identity: claim.Identity}, nil
	}
	if claim.ConsumedByAccountID == nil || *claim.ConsumedByAccountID == "" ||
		claim.RegistrationRequestID == nil || *claim.RegistrationRequestID == "" ||
		claim.ExistingVaultID == nil || *claim.ExistingVaultID == "" {
		return RegistrationResolution{}, ErrInvalidClaim
	}
	if *claim.RegistrationRequestID != registrationRequestID {
		return RegistrationResolution{}, ErrConsumedClaim
	}
	return RegistrationResolution{
		Identity: claim.Identity,
		Existing: &ExistingRegistration{
			AccountID: *claim.ConsumedByAccountID,
			VaultID:   *claim.ExistingVaultID,
		},
	}, nil
}

func validIdentity(identity Identity) bool {
	if identity.Issuer == "" || identity.Subject == "" || identity.IntentID == "" {
		return false
	}
	switch identity.Provider {
	case "apple", "google", "huawei":
		return true
	default:
		return false
	}
}
