package identityclaim

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"testing"
	"time"
)

var _ func(*PostgresRepository, context.Context, *sql.Tx, string) (*LockedClaim, error) = (*PostgresRepository).LockForRegistration

func TestIssuedClaimRedactsRawTokenFromFormattingLoggingAndJSON(t *testing.T) {
	randomBytes := bytes.Repeat([]byte{0x4a}, 32)
	rawToken := base64.RawURLEncoding.EncodeToString(randomBytes)
	service := newTestService(&recordingIssueRepository{}, randomBytes, time.Now())
	issued, err := service.Issue(context.Background(), Identity{
		Provider: "apple",
		Issuer:   "issuer",
		Subject:  "subject",
		IntentID: "01000000-0000-4000-8000-000000000001",
	})
	if err != nil {
		t.Fatalf("Issue() error = %v", err)
	}

	for _, format := range []string{"%v", "%+v", "%#v", "%q", "%s"} {
		formatted := fmt.Sprintf(format, issued)
		if strings.Contains(formatted, rawToken) || !strings.Contains(formatted, "<redacted>") {
			t.Fatalf("format %s did not redact token", format)
		}
	}
	var logOutput bytes.Buffer
	logger := slog.New(slog.NewJSONHandler(&logOutput, nil))
	logger.Info("issued claim", "claim", issued)
	if strings.Contains(logOutput.String(), rawToken) || !strings.Contains(logOutput.String(), "<redacted>") {
		t.Fatal("structured log did not redact token")
	}
	encoded, err := json.Marshal(issued)
	if err != nil {
		t.Fatalf("marshal issued claim: %v", err)
	}
	if strings.Contains(string(encoded), rawToken) {
		t.Fatal("JSON contains raw token")
	}
	if _, implementsStringer := any(issued).(fmt.Stringer); implementsStringer {
		t.Fatal("IssuedClaim implements fmt.Stringer")
	}
	if _, implementsStringer := any(&issued).(fmt.Stringer); implementsStringer {
		t.Fatal("*IssuedClaim implements fmt.Stringer")
	}
}

func TestConstructorsRejectNilDependencies(t *testing.T) {
	t.Run("service", func(t *testing.T) {
		assertPanics(t, func() { NewService(nil) })
	})
	t.Run("postgres repository", func(t *testing.T) {
		assertPanics(t, func() { NewPostgresRepository(nil) })
	})
}

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
	rawToken, ok := issued.TakeToken()
	if !ok {
		t.Fatal("TakeToken() did not return the token")
	}
	if secondToken, secondOK := issued.TakeToken(); secondOK || secondToken != "" {
		t.Fatal("TakeToken() returned the token more than once")
	}

	wantToken := base64.RawURLEncoding.EncodeToString(randomBytes)
	if rawToken != wantToken {
		t.Fatal("Issue() token does not match deterministic opaque token")
	}
	if strings.Contains(rawToken, "=") {
		t.Fatal("Issue() token is padded")
	}
	decoded, err := base64.RawURLEncoding.DecodeString(rawToken)
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
	if repository.claim.TokenSHA256 == rawToken || strings.Contains(fmt.Sprintf("%#v", repository.claim), rawToken) {
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
	if _, implementsStringer := any(rawToken).(fmt.Stringer); implementsStringer {
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

func TestIssueRejectsInvalidIntentID(t *testing.T) {
	for _, intentID := range []string{
		"not-a-uuid",
		"40000000-0000-4000-8000-00000000000A",
		"{40000000-0000-4000-8000-000000000001}",
	} {
		repository := &recordingIssueRepository{}
		service := newTestService(repository, bytes.Repeat([]byte{0x5a}, 32), time.Now())
		_, err := service.Issue(context.Background(), Identity{
			Provider: "apple",
			Issuer:   "issuer",
			Subject:  "subject",
			IntentID: intentID,
		})
		if !errors.Is(err, ErrInvalidIdentity) {
			t.Fatalf("Issue() error = %v, want ErrInvalidIdentity", err)
		}
		if repository.issueCalls != 0 {
			t.Fatalf("repository Issue() calls = %d, want 0", repository.issueCalls)
		}
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
	transaction := &sql.Tx{}
	claim := &LockedClaim{
		id:          "60000000-0000-4000-8000-000000000001",
		transaction: transaction,
		Identity:    identity,
		ExpiresAt:   now.Add(time.Minute),
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
	if resolution.PendingConsumption == nil {
		t.Fatal("resolved pending consumption = nil")
	}
	if resolution.PendingConsumption.transaction != transaction ||
		resolution.PendingConsumption.claimID != "60000000-0000-4000-8000-000000000001" ||
		resolution.PendingConsumption.registrationRequestID != "70000000-0000-4000-8000-000000000001" {
		t.Fatal("pending consumption is not bound to the locked claim, transaction, and request")
	}
}

func TestResolveForRegistrationRejectsInvalidRegistrationRequestID(t *testing.T) {
	now := time.Date(2026, time.July, 19, 10, 0, 0, 0, time.UTC)
	service := newTestService(&recordingIssueRepository{}, bytes.Repeat([]byte{1}, 32), now)
	claim := &LockedClaim{
		id:          "61000000-0000-4000-8000-000000000001",
		transaction: &sql.Tx{},
		ExpiresAt:   now.Add(time.Minute),
	}
	for _, requestID := range []string{"", "request-id", "70000000-0000-4000-8000-00000000000A"} {
		resolution, err := service.ResolveForRegistration(claim, requestID)
		if !errors.Is(err, ErrInvalidClaim) {
			t.Fatalf("ResolveForRegistration() error = %v, want ErrInvalidClaim", err)
		}
		if resolution.PendingConsumption != nil {
			t.Fatal("invalid request returned pending consumption")
		}
	}
}

func TestResolveForRegistrationRejectsExpiredClaim(t *testing.T) {
	now := time.Date(2026, time.July, 19, 10, 0, 0, 0, time.UTC)
	service := newTestService(&recordingIssueRepository{}, bytes.Repeat([]byte{1}, 32), now)
	transaction := &sql.Tx{}

	for _, expiresAt := range []time.Time{now.Add(-time.Nanosecond), now} {
		claim := &LockedClaim{
			id:          "62000000-0000-4000-8000-000000000001",
			transaction: transaction,
			ExpiresAt:   expiresAt,
		}
		_, err := service.ResolveForRegistration(claim, "72000000-0000-4000-8000-000000000001")
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
		id:                    "63000000-0000-4000-8000-000000000001",
		transaction:           &sql.Tx{},
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
	if resolution.PendingConsumption != nil {
		t.Fatal("consumed replay returned pending consumption")
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
		id:                    "64000000-0000-4000-8000-000000000001",
		transaction:           &sql.Tx{},
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
	accountID := "82000000-0000-4000-8000-000000000001"
	vaultID := "92000000-0000-4000-8000-000000000001"
	originalRequestID := "a2000000-0000-4000-8000-000000000001"
	claim := &LockedClaim{
		id:                    "65000000-0000-4000-8000-000000000001",
		transaction:           &sql.Tx{},
		ExpiresAt:             now.Add(time.Minute),
		ConsumedAt:            &consumedAt,
		ConsumedByAccountID:   &accountID,
		RegistrationRequestID: &originalRequestID,
		ExistingVaultID:       &vaultID,
	}

	_, err := service.ResolveForRegistration(claim, "a3000000-0000-4000-8000-000000000001")
	if !errors.Is(err, ErrConsumedClaim) {
		t.Fatalf("ResolveForRegistration() error = %v, want ErrConsumedClaim", err)
	}
}

func TestResolveForRegistrationRejectsDifferentRequestForExpiredConsumedClaim(t *testing.T) {
	now := time.Date(2026, time.July, 19, 10, 0, 0, 0, time.UTC)
	service := newTestService(&recordingIssueRepository{}, bytes.Repeat([]byte{1}, 32), now)
	consumedAt := now.Add(-time.Hour)
	accountID := "83000000-0000-4000-8000-000000000001"
	vaultID := "93000000-0000-4000-8000-000000000001"
	originalRequestID := "a4000000-0000-4000-8000-000000000001"
	claim := &LockedClaim{
		id:                    "66000000-0000-4000-8000-000000000001",
		transaction:           &sql.Tx{},
		ExpiresAt:             now,
		ConsumedAt:            &consumedAt,
		ConsumedByAccountID:   &accountID,
		RegistrationRequestID: &originalRequestID,
		ExistingVaultID:       &vaultID,
	}

	_, err := service.ResolveForRegistration(claim, "a5000000-0000-4000-8000-000000000001")
	if !errors.Is(err, ErrConsumedClaim) {
		t.Fatalf("ResolveForRegistration() error = %v, want ErrConsumedClaim", err)
	}
}

func TestResolveForRegistrationRejectsUnknownOrInconsistentClaim(t *testing.T) {
	now := time.Date(2026, time.July, 19, 10, 0, 0, 0, time.UTC)
	service := newTestService(&recordingIssueRepository{}, bytes.Repeat([]byte{1}, 32), now)
	requestID := "a6000000-0000-4000-8000-000000000001"
	consumedAt := now.Add(-time.Minute)

	tests := []struct {
		name  string
		claim *LockedClaim
	}{
		{name: "unknown", claim: nil},
		{name: "missing id", claim: &LockedClaim{transaction: &sql.Tx{}, ExpiresAt: now.Add(time.Minute)}},
		{
			name: "incomplete consumed state",
			claim: &LockedClaim{
				id:                    "67000000-0000-4000-8000-000000000001",
				transaction:           &sql.Tx{},
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

func TestParseTokenDigestRequiresCanonical32ByteBase64URL(t *testing.T) {
	validToken := base64.RawURLEncoding.EncodeToString(bytes.Repeat([]byte{0}, 32))
	digest, err := parseTokenDigest(validToken)
	if err != nil {
		t.Fatalf("parseTokenDigest() error = %v", err)
	}
	if digest != tokenSHA256(validToken) {
		t.Fatalf("parseTokenDigest() digest = %q", digest)
	}

	nonCanonical := validToken[:len(validToken)-1] + "B"
	for _, rawToken := range []string{
		"",
		validToken + "=",
		base64.RawURLEncoding.EncodeToString(bytes.Repeat([]byte{0}, 31)),
		nonCanonical,
		strings.Repeat("+", len(validToken)),
	} {
		if _, err := parseTokenDigest(rawToken); !errors.Is(err, ErrInvalidClaim) {
			t.Fatalf("parseTokenDigest() error = %v, want ErrInvalidClaim", err)
		}
	}
}

func TestLockForRegistrationRejectsInvalidInputsBeforeQuery(t *testing.T) {
	repository := NewPostgresRepository(&sql.DB{})
	validToken := base64.RawURLEncoding.EncodeToString(bytes.Repeat([]byte{0}, 32))
	tests := []struct {
		name        string
		transaction *sql.Tx
		rawToken    string
	}{
		{name: "nil transaction", transaction: nil, rawToken: validToken},
		{name: "empty token", transaction: &sql.Tx{}, rawToken: ""},
		{name: "padded token", transaction: &sql.Tx{}, rawToken: validToken + "="},
		{name: "short token", transaction: &sql.Tx{}, rawToken: base64.RawURLEncoding.EncodeToString(make([]byte, 31))},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, err := repository.LockForRegistration(context.Background(), test.transaction, test.rawToken)
			if !errors.Is(err, ErrInvalidClaim) {
				t.Fatalf("LockForRegistration() error = %v, want ErrInvalidClaim", err)
			}
		})
	}
}

func TestMarkConsumedRejectsInvalidCapabilityAndUUIDsBeforeSQL(t *testing.T) {
	repository := NewPostgresRepository(&sql.DB{})
	transaction := &sql.Tx{}
	otherTransaction := &sql.Tx{}
	requestID := "a7000000-0000-4000-8000-000000000001"
	accountID := "84000000-0000-4000-8000-000000000001"
	validPending := &PendingConsumption{
		claimID:               "68000000-0000-4000-8000-000000000001",
		transaction:           transaction,
		registrationRequestID: requestID,
	}
	tests := []struct {
		name                  string
		transaction           *sql.Tx
		pending               *PendingConsumption
		accountID             string
		registrationRequestID string
	}{
		{name: "nil transaction", pending: validPending, accountID: accountID, registrationRequestID: requestID},
		{name: "nil capability", transaction: transaction, accountID: accountID, registrationRequestID: requestID},
		{name: "mismatched transaction", transaction: otherTransaction, pending: validPending, accountID: accountID, registrationRequestID: requestID},
		{name: "malformed claim", transaction: transaction, pending: &PendingConsumption{claimID: "bad", transaction: transaction, registrationRequestID: requestID}, accountID: accountID, registrationRequestID: requestID},
		{name: "mismatched request", transaction: transaction, pending: validPending, accountID: accountID, registrationRequestID: "a8000000-0000-4000-8000-000000000001"},
		{name: "invalid account", transaction: transaction, pending: validPending, accountID: "account-id", registrationRequestID: requestID},
		{name: "invalid request", transaction: transaction, pending: validPending, accountID: accountID, registrationRequestID: "request-id"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			err := repository.MarkConsumed(
				context.Background(),
				test.transaction,
				test.pending,
				time.Now(),
				test.accountID,
				test.registrationRequestID,
			)
			if !errors.Is(err, ErrInvalidClaim) {
				t.Fatalf("MarkConsumed() error = %v, want ErrInvalidClaim", err)
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

func assertPanics(t *testing.T, operation func()) {
	t.Helper()
	defer func() {
		if recover() == nil {
			t.Fatal("operation did not panic")
		}
	}()
	operation()
}
