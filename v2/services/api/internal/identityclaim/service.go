package identityclaim

import (
	"context"
	"crypto/rand"
	"fmt"
	"io"
	"reflect"
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
	if nilDependency(repository) {
		panic("identityclaim: nil issue repository")
	}
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
		secret:    &issuedClaimSecret{rawToken: rawToken},
		Provider:  identity.Provider,
		ExpiresIn: claimLifetime,
	}, nil
}

func (service *Service) ResolveForRegistration(
	claim *LockedClaim,
	registrationRequestID string,
) (RegistrationResolution, error) {
	if !canonicalUUID(registrationRequestID) || claim == nil ||
		!canonicalUUID(claim.id) || claim.transaction == nil || claim.expiresAt.IsZero() {
		return RegistrationResolution{}, ErrInvalidClaim
	}
	if claim.consumedAt == nil {
		if claim.consumedByAccountID != nil || claim.registrationRequestID != nil || claim.existingVaultID != nil {
			return RegistrationResolution{}, ErrInvalidClaim
		}
		if !claim.expiresAt.After(service.now()) {
			return RegistrationResolution{}, ErrExpiredClaim
		}
		return RegistrationResolution{
			Identity: claim.identity,
			PendingConsumption: &PendingConsumption{
				claimID:               claim.id,
				transaction:           claim.transaction,
				registrationRequestID: registrationRequestID,
			},
		}, nil
	}
	if claim.consumedByAccountID == nil || *claim.consumedByAccountID == "" ||
		claim.registrationRequestID == nil || *claim.registrationRequestID == "" ||
		claim.existingVaultID == nil || *claim.existingVaultID == "" {
		return RegistrationResolution{}, ErrInvalidClaim
	}
	if *claim.registrationRequestID != registrationRequestID {
		return RegistrationResolution{}, ErrConsumedClaim
	}
	return RegistrationResolution{
		Identity: claim.identity,
		Existing: &ExistingRegistration{
			AccountID: *claim.consumedByAccountID,
			VaultID:   *claim.existingVaultID,
		},
	}, nil
}

func validIdentity(identity Identity) bool {
	if identity.Issuer == "" || identity.Subject == "" || !canonicalUUID(identity.IntentID) {
		return false
	}
	switch identity.Provider {
	case "apple", "google", "huawei":
		return true
	default:
		return false
	}
}

func canonicalUUID(value string) bool {
	parsed, err := uuid.Parse(value)
	return err == nil && parsed != uuid.Nil && parsed.String() == value
}

func nilDependency(dependency any) bool {
	if dependency == nil {
		return true
	}
	value := reflect.ValueOf(dependency)
	switch value.Kind() {
	case reflect.Chan, reflect.Func, reflect.Interface, reflect.Map, reflect.Pointer, reflect.Slice:
		return value.IsNil()
	default:
		return false
	}
}
