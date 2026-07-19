package identityclaim

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"
)

func TestIssueStoresDigestAndReturnsOpaqueToken(t *testing.T) {
	now := time.Date(2026, time.July, 19, 8, 30, 0, 0, time.UTC)
	randomBytes := make([]byte, 32)
	for index := range randomBytes {
		randomBytes[index] = byte(index)
	}
	repository := &recordingIssueRepository{}
	service := newTestService(repository, randomBytes, now)
	identity := Identity{
		Provider: "apple",
		Issuer:   "https://appleid.apple.com",
		Subject:  "stable-subject",
		IntentID: "10000000-0000-4000-8000-000000000001",
	}

	issued, err := service.Issue(context.Background(), identity)
	if err != nil {
		t.Fatalf("Issue() error = %v", err)
	}

	wantToken := base64.RawURLEncoding.EncodeToString(randomBytes)
	if issued.Token != wantToken {
		t.Fatal("Issue() token does not match deterministic opaque token")
	}
	if strings.Contains(issued.Token, "=") {
		t.Fatal("Issue() token is padded")
	}
	decoded, err := base64.RawURLEncoding.DecodeString(issued.Token)
	if err != nil {
		t.Fatalf("decode issued token: %v", err)
	}
	if len(decoded) != 32 {
		t.Fatalf("decoded token length = %d, want 32", len(decoded))
	}
	if issued.Provider != identity.Provider || issued.ExpiresIn != 10*time.Minute {
		t.Fatalf("Issue() result = %#v", issued)
	}
	if repository.issueCalls != 1 {
		t.Fatalf("repository Issue() calls = %d, want 1", repository.issueCalls)
	}
	wantDigestBytes := sha256.Sum256([]byte(wantToken))
	wantDigest := hex.EncodeToString(wantDigestBytes[:])
	if repository.claim.TokenSHA256 != wantDigest {
		t.Fatalf("stored digest = %q, want %q", repository.claim.TokenSHA256, wantDigest)
	}
	if repository.claim.TokenSHA256 == issued.Token || strings.Contains(fmt.Sprintf("%#v", repository.claim), issued.Token) {
		t.Fatal("stored claim contains the raw token")
	}
	if repository.claim.Identity != identity {
		t.Fatalf("stored identity = %#v, want %#v", repository.claim.Identity, identity)
	}
	if repository.claim.ID != "20000000-0000-4000-8000-000000000001" {
		t.Fatalf("stored claim ID = %q", repository.claim.ID)
	}
	if !repository.claim.ExpiresAt.Equal(now.Add(10 * time.Minute)) {
		t.Fatalf("stored expiry = %v", repository.claim.ExpiresAt)
	}
	if _, implementsStringer := any(issued.Token).(fmt.Stringer); implementsStringer {
		t.Fatal("claim token implements fmt.Stringer")
	}
}

func TestIssuePreservesSupportedProviderIdentity(t *testing.T) {
	for _, provider := range []string{"apple", "google", "huawei"} {
		t.Run(provider, func(t *testing.T) {
			repository := &recordingIssueRepository{}
			service := newTestService(repository, bytes.Repeat([]byte{0x5a}, 32), time.Now())
			identity := Identity{
				Provider: provider,
				Issuer:   "issuer-exact-value",
				Subject:  "subject-exact-value",
				IntentID: "30000000-0000-4000-8000-000000000001",
			}

			if _, err := service.Issue(context.Background(), identity); err != nil {
				t.Fatalf("Issue() error = %v", err)
			}
			if repository.claim.Identity != identity {
				t.Fatalf("stored identity = %#v, want %#v", repository.claim.Identity, identity)
			}
		})
	}
}

func TestIssueRejectsUnsupportedProvider(t *testing.T) {
	repository := &recordingIssueRepository{}
	service := newTestService(repository, bytes.Repeat([]byte{0x5a}, 32), time.Now())

	_, err := service.Issue(context.Background(), Identity{
		Provider: "wechat",
		Issuer:   "issuer",
		Subject:  "subject",
		IntentID: "40000000-0000-4000-8000-000000000001",
	})
	if !errors.Is(err, ErrInvalidIdentity) {
		t.Fatalf("Issue() error = %v, want ErrInvalidIdentity", err)
	}
	if repository.issueCalls != 0 {
		t.Fatalf("repository Issue() calls = %d, want 0", repository.issueCalls)
	}
}

func TestResolveForRegistrationAcceptsValidUnconsumedClaim(t *testing.T) {
	now := time.Date(2026, time.July, 19, 10, 0, 0, 0, time.UTC)
	service := newTestService(&recordingIssueRepository{}, bytes.Repeat([]byte{1}, 32), now)
	identity := Identity{
		Provider: "google",
		Issuer:   "https://accounts.google.com",
		Subject:  "google-subject",
		IntentID: "50000000-0000-4000-8000-000000000001",
	}
	claim := &LockedClaim{
		ID:        "60000000-0000-4000-8000-000000000001",
		Identity:  identity,
		ExpiresAt: now.Add(time.Minute),
	}

	resolution, err := service.ResolveForRegistration(claim, "70000000-0000-4000-8000-000000000001")
	if err != nil {
		t.Fatalf("ResolveForRegistration() error = %v", err)
	}
	if resolution.Identity != identity {
		t.Fatalf("resolved identity = %#v, want %#v", resolution.Identity, identity)
	}
	if resolution.Existing != nil {
		t.Fatalf("resolved existing registration = %#v, want nil", resolution.Existing)
	}
}

func TestResolveForRegistrationRejectsExpiredClaim(t *testing.T) {
	now := time.Date(2026, time.July, 19, 10, 0, 0, 0, time.UTC)
	service := newTestService(&recordingIssueRepository{}, bytes.Repeat([]byte{1}, 32), now)

	for _, expiresAt := range []time.Time{now.Add(-time.Nanosecond), now} {
		claim := &LockedClaim{ID: "claim-id", ExpiresAt: expiresAt}
		_, err := service.ResolveForRegistration(claim, "request-id")
		if !errors.Is(err, ErrExpiredClaim) {
			t.Fatalf("expiry %v error = %v, want ErrExpiredClaim", expiresAt, err)
		}
	}
}

func TestResolveForRegistrationReplaysSameRequest(t *testing.T) {
	now := time.Date(2026, time.July, 19, 10, 0, 0, 0, time.UTC)
	service := newTestService(&recordingIssueRepository{}, bytes.Repeat([]byte{1}, 32), now)
	consumedAt := now.Add(-time.Minute)
	accountID := "80000000-0000-4000-8000-000000000001"
	vaultID := "90000000-0000-4000-8000-000000000001"
	requestID := "a0000000-0000-4000-8000-000000000001"
	claim := &LockedClaim{
		ID:                    "claim-id",
		Identity:              Identity{Provider: "huawei", Issuer: "issuer", Subject: "subject", IntentID: "intent"},
		ExpiresAt:             now.Add(time.Minute),
		ConsumedAt:            &consumedAt,
		ConsumedByAccountID:   &accountID,
		RegistrationRequestID: &requestID,
		ExistingVaultID:       &vaultID,
	}

	resolution, err := service.ResolveForRegistration(claim, requestID)
	if err != nil {
		t.Fatalf("ResolveForRegistration() error = %v", err)
	}
	if resolution.Existing == nil || resolution.Existing.AccountID != accountID || resolution.Existing.VaultID != vaultID {
		t.Fatalf("existing registration = %#v", resolution.Existing)
	}
	if resolution.Identity != claim.Identity {
		t.Fatalf("resolved identity = %#v, want %#v", resolution.Identity, claim.Identity)
	}
}

func TestResolveForRegistrationReplaysExpiredConsumedClaimForSameRequest(t *testing.T) {
	now := time.Date(2026, time.July, 19, 10, 0, 0, 0, time.UTC)
	service := newTestService(&recordingIssueRepository{}, bytes.Repeat([]byte{1}, 32), now)
	consumedAt := now.Add(-time.Hour)
	accountID := "81000000-0000-4000-8000-000000000001"
	vaultID := "91000000-0000-4000-8000-000000000001"
	requestID := "a1000000-0000-4000-8000-000000000001"
	claim := &LockedClaim{
		ID:                    "claim-id",
		Identity:              Identity{Provider: "apple", Issuer: "issuer", Subject: "subject", IntentID: "intent"},
		ExpiresAt:             now.Add(-time.Minute),
		ConsumedAt:            &consumedAt,
		ConsumedByAccountID:   &accountID,
		RegistrationRequestID: &requestID,
		ExistingVaultID:       &vaultID,
	}

	resolution, err := service.ResolveForRegistration(claim, requestID)
	if err != nil {
		t.Fatalf("ResolveForRegistration() error = %v", err)
	}
	if resolution.Existing == nil || resolution.Existing.AccountID != accountID || resolution.Existing.VaultID != vaultID {
		t.Fatalf("existing registration = %#v", resolution.Existing)
	}
}

func TestResolveForRegistrationRejectsDifferentRequest(t *testing.T) {
	now := time.Date(2026, time.July, 19, 10, 0, 0, 0, time.UTC)
	service := newTestService(&recordingIssueRepository{}, bytes.Repeat([]byte{1}, 32), now)
	consumedAt := now.Add(-time.Minute)
	accountID := "account-id"
	vaultID := "vault-id"
	originalRequestID := "original-request"
	claim := &LockedClaim{
		ID:                    "claim-id",
		ExpiresAt:             now.Add(time.Minute),
		ConsumedAt:            &consumedAt,
		ConsumedByAccountID:   &accountID,
		RegistrationRequestID: &originalRequestID,
		ExistingVaultID:       &vaultID,
	}

	_, err := service.ResolveForRegistration(claim, "different-request")
	if !errors.Is(err, ErrConsumedClaim) {
		t.Fatalf("ResolveForRegistration() error = %v, want ErrConsumedClaim", err)
	}
}

func TestResolveForRegistrationRejectsDifferentRequestForExpiredConsumedClaim(t *testing.T) {
	now := time.Date(2026, time.July, 19, 10, 0, 0, 0, time.UTC)
	service := newTestService(&recordingIssueRepository{}, bytes.Repeat([]byte{1}, 32), now)
	consumedAt := now.Add(-time.Hour)
	accountID := "account-id"
	vaultID := "vault-id"
	originalRequestID := "original-request"
	claim := &LockedClaim{
		ID:                    "claim-id",
		ExpiresAt:             now,
		ConsumedAt:            &consumedAt,
		ConsumedByAccountID:   &accountID,
		RegistrationRequestID: &originalRequestID,
		ExistingVaultID:       &vaultID,
	}

	_, err := service.ResolveForRegistration(claim, "different-request")
	if !errors.Is(err, ErrConsumedClaim) {
		t.Fatalf("ResolveForRegistration() error = %v, want ErrConsumedClaim", err)
	}
}

func TestResolveForRegistrationRejectsUnknownOrInconsistentClaim(t *testing.T) {
	now := time.Date(2026, time.July, 19, 10, 0, 0, 0, time.UTC)
	service := newTestService(&recordingIssueRepository{}, bytes.Repeat([]byte{1}, 32), now)
	requestID := "request-id"
	consumedAt := now.Add(-time.Minute)

	tests := []struct {
		name  string
		claim *LockedClaim
	}{
		{name: "unknown", claim: nil},
		{name: "missing id", claim: &LockedClaim{ExpiresAt: now.Add(time.Minute)}},
		{
			name: "incomplete consumed state",
			claim: &LockedClaim{
				ID:                    "claim-id",
				ExpiresAt:             now.Add(time.Minute),
				ConsumedAt:            &consumedAt,
				RegistrationRequestID: &requestID,
			},
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, err := service.ResolveForRegistration(test.claim, requestID)
			if !errors.Is(err, ErrInvalidClaim) {
				t.Fatalf("ResolveForRegistration() error = %v, want ErrInvalidClaim", err)
			}
		})
	}
}

func TestClaimErrorsNeverContainRawToken(t *testing.T) {
	rawToken := base64.RawURLEncoding.EncodeToString(bytes.Repeat([]byte{0xfa}, 32))
	for _, err := range []error{ErrInvalidClaim, ErrExpiredClaim, ErrConsumedClaim, ErrInvalidIdentity} {
		if strings.Contains(err.Error(), rawToken) {
			t.Fatal("stable identity claim error contains raw token")
		}
	}

	repository := &recordingIssueRepository{err: errors.New("database unavailable")}
	service := newTestService(repository, bytes.Repeat([]byte{0xfa}, 32), time.Now())
	_, err := service.Issue(context.Background(), Identity{
		Provider: "apple",
		Issuer:   "issuer",
		Subject:  "subject",
		IntentID: "b0000000-0000-4000-8000-000000000001",
	})
	if err == nil {
		t.Fatal("Issue() error = nil, want repository error")
	}
	if strings.Contains(err.Error(), rawToken) {
		t.Fatal("Issue() error contains raw token")
	}
}

type recordingIssueRepository struct {
	claim      StoredClaim
	issueCalls int
	err        error
}

func (repository *recordingIssueRepository) Issue(_ context.Context, claim StoredClaim) error {
	repository.issueCalls++
	repository.claim = claim
	return repository.err
}

func newTestService(
	repository IssueRepository,
	randomBytes []byte,
	now time.Time,
) *Service {
	return &Service{
		repository:   repository,
		randomSource: bytes.NewReader(randomBytes),
		now:          func() time.Time { return now },
		newID:        func() string { return "20000000-0000-4000-8000-000000000001" },
	}
}
