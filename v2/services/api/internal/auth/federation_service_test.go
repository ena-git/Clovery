package auth

import (
	"bytes"
	"context"
	"crypto/sha256"
	"errors"
	"testing"
	"time"
)

func TestFederationBindingRequiresRecentCloverySession(t *testing.T) {
	provider := &stubIdentityProvider{name: "apple"}
	store := &stubFederationStore{}
	service, err := NewFederationService(
		stubRecentSessionAuthenticator{err: ErrInvalidSession},
		store,
		[]IdentityProvider{provider},
	)
	if err != nil {
		t.Fatalf("create federation service: %v", err)
	}

	_, err = service.StartBinding(context.Background(), "third-party-code-only", "apple")
	if !errors.Is(err, ErrRecentAuthenticationRequired) {
		t.Fatalf("start binding error = %v", err)
	}
	if store.createCalls != 0 {
		t.Fatalf("binding intents created = %d", store.createCalls)
	}
}

func TestFederatedLoginDoesNotMergeAccountsByEmail(t *testing.T) {
	provider := &stubIdentityProvider{
		name: "google",
		identity: VerifiedIdentity{
			Issuer:  "https://accounts.google.com",
			Subject: "new-google-subject",
			Email:   "existing@clovery.example",
		},
	}
	store := &stubFederationStore{findErr: ErrFederatedIdentityNotBound}
	service, err := NewFederationService(
		stubRecentSessionAuthenticator{},
		store,
		[]IdentityProvider{provider},
	)
	if err != nil {
		t.Fatalf("create federation service: %v", err)
	}

	_, err = service.CompleteLogin(context.Background(), FederatedLoginCommand{
		IntentID:          "11111111-1111-4111-8111-111111111111",
		Provider:          "google",
		AuthorizationCode: "authorization-code",
		Nonce:             "federation-nonce",
	})
	if !errors.Is(err, ErrFederatedIdentityNotBound) {
		t.Fatalf("complete login error = %v", err)
	}
	if store.lookup.Provider != "google" ||
		store.lookup.Issuer != provider.identity.Issuer ||
		store.lookup.Subject != provider.identity.Subject {
		t.Fatalf("identity lookup = %#v", store.lookup)
	}
}

func TestFederatedIdentityCannotBindToTwoAccounts(t *testing.T) {
	provider := &stubIdentityProvider{
		name: "apple",
		identity: VerifiedIdentity{
			Issuer:  "https://appleid.apple.com",
			Subject: "stable-apple-subject",
		},
	}
	store := &stubFederationStore{bindErr: ErrFederatedIdentityAlreadyBound}
	service, err := NewFederationService(
		stubRecentSessionAuthenticator{claims: AccessClaims{
			AccountID: "22222222-2222-4222-8222-222222222222",
			SessionID: "33333333-3333-4333-8333-333333333333",
		}},
		store,
		[]IdentityProvider{provider},
	)
	if err != nil {
		t.Fatalf("create federation service: %v", err)
	}

	err = service.CompleteBinding(context.Background(), FederatedBindingCommand{
		AccessToken:       "recent-clovery-access-token",
		IntentID:          "44444444-4444-4444-8444-444444444444",
		Provider:          "apple",
		AuthorizationCode: "authorization-code",
		Nonce:             "binding-nonce",
	})
	if !errors.Is(err, ErrFederatedIdentityAlreadyBound) {
		t.Fatalf("complete binding error = %v", err)
	}
	if store.boundAccountID != "22222222-2222-4222-8222-222222222222" {
		t.Fatalf("bound account ID = %q", store.boundAccountID)
	}
}

func TestCannotUnbindLastRecoveryCredential(t *testing.T) {
	store := &stubFederationStore{unbindErr: ErrLastRecoveryCredential}
	service, err := NewFederationService(
		stubRecentSessionAuthenticator{claims: AccessClaims{
			AccountID: "55555555-5555-4555-8555-555555555555",
		}},
		store,
		[]IdentityProvider{&stubIdentityProvider{name: "huawei"}},
	)
	if err != nil {
		t.Fatalf("create federation service: %v", err)
	}

	err = service.UnbindIdentity(context.Background(), FederatedUnbindingCommand{
		AccessToken: "recent-clovery-access-token",
		Provider:    "huawei",
	})
	if !errors.Is(err, ErrLastRecoveryCredential) {
		t.Fatalf("unbind identity error = %v", err)
	}
}

func TestFederatedLoginStartsWithHashedExpiringNonce(t *testing.T) {
	store := &stubFederationStore{}
	service, err := NewFederationService(
		stubRecentSessionAuthenticator{},
		store,
		[]IdentityProvider{&stubIdentityProvider{name: "google"}},
	)
	if err != nil {
		t.Fatalf("create federation service: %v", err)
	}
	now := time.Date(2026, time.July, 14, 10, 0, 0, 0, time.UTC)
	service.now = func() time.Time { return now }
	service.random = bytes.NewReader(make([]byte, 48))

	intent, err := service.StartLogin(context.Background(), " Google ")
	if err != nil {
		t.Fatalf("start federated login: %v", err)
	}
	if intent.Provider != "google" || intent.Nonce == "" {
		t.Fatalf("login intent = %#v", intent)
	}
	expectedHash := sha256.Sum256([]byte(intent.Nonce))
	if !bytes.Equal(store.loginIntent.NonceHash, expectedHash[:]) {
		t.Fatal("stored login nonce hash does not match returned nonce")
	}
	if bytes.Equal(store.loginIntent.NonceHash, []byte(intent.Nonce)) {
		t.Fatal("login nonce was stored in plaintext")
	}
	if !store.loginIntent.ExpiresAt.Equal(now.Add(10 * time.Minute)) {
		t.Fatalf("login intent expiry = %v", store.loginIntent.ExpiresAt)
	}
}

type stubRecentSessionAuthenticator struct {
	claims AccessClaims
	err    error
}

func (stub stubRecentSessionAuthenticator) AuthenticateRecent(
	context.Context,
	string,
	time.Duration,
) (AccessClaims, error) {
	return stub.claims, stub.err
}

type stubIdentityProvider struct {
	name     string
	identity VerifiedIdentity
	err      error
}

func (provider *stubIdentityProvider) Name() string {
	return provider.name
}

func (provider *stubIdentityProvider) Verify(
	context.Context,
	string,
	string,
) (VerifiedIdentity, error) {
	return provider.identity, provider.err
}

type stubFederationStore struct {
	createCalls     int
	lookup          FederatedIdentityKey
	findErr         error
	bindErr         error
	boundAccountID  string
	unbindErr       error
	unboundProvider string
	loginIntent     FederatedLoginIntentRecord
}

func (store *stubFederationStore) CreateBindingIntent(
	context.Context,
	BindingIntentRecord,
) error {
	store.createCalls++
	return nil
}

func (store *stubFederationStore) CreateLoginIntent(
	_ context.Context,
	intent FederatedLoginIntentRecord,
) error {
	store.loginIntent = intent
	return nil
}

func (store *stubFederationStore) ConsumeLoginIntent(
	context.Context,
	ConsumeFederatedLoginIntent,
) error {
	return nil
}

func (store *stubFederationStore) FindAccountByIdentity(
	_ context.Context,
	key FederatedIdentityKey,
) (FederatedAccount, error) {
	store.lookup = key
	return FederatedAccount{}, store.findErr
}

func (store *stubFederationStore) ConsumeBindingIntent(
	context.Context,
	ConsumeFederatedBindingIntent,
) error {
	return nil
}

func (store *stubFederationStore) BindIdentity(
	_ context.Context,
	accountID string,
	_ FederatedIdentityKey,
) error {
	store.boundAccountID = accountID
	return store.bindErr
}

func (store *stubFederationStore) UnbindIdentity(
	_ context.Context,
	_ string,
	provider string,
) error {
	store.unboundProvider = provider
	return store.unbindErr
}
