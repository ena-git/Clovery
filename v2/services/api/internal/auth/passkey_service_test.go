package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"
)

func TestPasskeyRegistrationChallengeIsBoundToRecentSession(t *testing.T) {
	store := &stubPasskeyStore{user: PasskeyUser{
		AccountID: "11111111-1111-4111-8111-111111111111",
		VaultID:   "22222222-2222-4222-8222-222222222222",
		Handle:    bytes.Repeat([]byte{1}, 32),
		Name:      "garden_user",
	}}
	engine := &stubPasskeyEngine{
		registrationOptions: json.RawMessage(`{"publicKey":{"challenge":"challenge"}}`),
		sessionData:         []byte(`{"challenge":"challenge"}`),
	}
	service, err := NewPasskeyService(
		stubRecentSessionAuthenticator{claims: AccessClaims{
			AccountID: "11111111-1111-4111-8111-111111111111",
			SessionID: "33333333-3333-4333-8333-333333333333",
		}},
		store,
		engine,
	)
	if err != nil {
		t.Fatalf("create passkey service: %v", err)
	}
	now := time.Date(2026, time.July, 14, 12, 0, 0, 0, time.UTC)
	service.now = func() time.Time { return now }
	service.random = bytes.NewReader(make([]byte, 16))

	result, err := service.BeginRegistration(context.Background(), "recent-access-token")
	if err != nil {
		t.Fatalf("begin passkey registration: %v", err)
	}
	if !bytes.Equal(result.Options, engine.registrationOptions) {
		t.Fatalf("registration options = %s", result.Options)
	}
	if store.challenge.AccountID != store.user.AccountID ||
		store.challenge.SessionID != "33333333-3333-4333-8333-333333333333" ||
		store.challenge.Purpose != PasskeyChallengeRegistration {
		t.Fatalf("stored passkey challenge = %#v", store.challenge)
	}
	if !store.challenge.ExpiresAt.Equal(now.Add(5 * time.Minute)) {
		t.Fatalf("challenge expiry = %v", store.challenge.ExpiresAt)
	}
}

func TestPasskeyRegistrationConsumesBoundChallengeBeforeSavingCredential(t *testing.T) {
	credential := PasskeyCredential{
		ID:        []byte("credential-id"),
		PublicKey: []byte("cose-public-key"),
		Record:    []byte(`{"id":"credential-id"}`),
		SignCount: 1,
	}
	store := &stubPasskeyStore{
		user: PasskeyUser{
			AccountID: "44444444-4444-4444-8444-444444444444",
			VaultID:   "55555555-5555-4555-8555-555555555555",
			Handle:    bytes.Repeat([]byte{2}, 32),
			Name:      "passkey_user",
		},
		consumedSessionData: []byte(`{"challenge":"stored"}`),
	}
	engine := &stubPasskeyEngine{credential: credential}
	service, err := NewPasskeyService(
		stubRecentSessionAuthenticator{claims: AccessClaims{
			AccountID: store.user.AccountID,
			SessionID: "66666666-6666-4666-8666-666666666666",
		}},
		store,
		engine,
	)
	if err != nil {
		t.Fatalf("create passkey service: %v", err)
	}
	service.now = func() time.Time {
		return time.Date(2026, time.July, 14, 12, 30, 0, 0, time.UTC)
	}

	err = service.CompleteRegistration(context.Background(), PasskeyRegistrationCommand{
		AccessToken: "recent-access-token",
		ChallengeID: "77777777-7777-4777-8777-777777777777",
		Response:    json.RawMessage(`{"id":"credential-response"}`),
	})
	if err != nil {
		t.Fatalf("complete passkey registration: %v", err)
	}
	if store.consumed.AccountID != store.user.AccountID ||
		store.consumed.SessionID != "66666666-6666-4666-8666-666666666666" ||
		store.consumed.Purpose != PasskeyChallengeRegistration {
		t.Fatalf("consumed challenge = %#v", store.consumed)
	}
	if !bytes.Equal(store.savedCredential.ID, credential.ID) {
		t.Fatalf("saved credential = %#v", store.savedCredential)
	}
}

func TestPasskeyRegistrationRejectsCredentialWithoutPublicKey(t *testing.T) {
	store := &stubPasskeyStore{
		user: PasskeyUser{
			AccountID: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
			Handle:    bytes.Repeat([]byte{4}, 32),
			Name:      "invalid_passkey_user",
		},
		consumedSessionData: []byte(`{"challenge":"stored"}`),
	}
	engine := &stubPasskeyEngine{credential: PasskeyCredential{
		ID:     []byte("credential-without-public-key"),
		Record: []byte(`{"id":"credential-without-public-key"}`),
	}}
	service, err := NewPasskeyService(
		stubRecentSessionAuthenticator{claims: AccessClaims{
			AccountID: store.user.AccountID,
			SessionID: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
		}},
		store,
		engine,
	)
	if err != nil {
		t.Fatalf("create passkey service: %v", err)
	}

	err = service.CompleteRegistration(context.Background(), PasskeyRegistrationCommand{
		AccessToken: "recent-access-token",
		ChallengeID: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
		Response:    json.RawMessage(`{"id":"response"}`),
	})
	if !errors.Is(err, ErrPasskeyAuthentication) {
		t.Fatalf("credential without public key error = %v", err)
	}
	if store.saveCalls != 0 {
		t.Fatalf("saved incomplete credentials = %d", store.saveCalls)
	}
}

func TestPasskeyLoginChallengeIsNotPreboundToAnAccount(t *testing.T) {
	store := &stubPasskeyStore{}
	engine := &stubPasskeyEngine{
		loginOptions:     json.RawMessage(`{"publicKey":{"challenge":"discoverable"}}`),
		loginSessionData: []byte(`{"challenge":"discoverable"}`),
	}
	service, err := NewPasskeyService(stubRecentSessionAuthenticator{}, store, engine)
	if err != nil {
		t.Fatalf("create passkey service: %v", err)
	}
	service.now = func() time.Time {
		return time.Date(2026, time.July, 14, 13, 0, 0, 0, time.UTC)
	}
	service.random = bytes.NewReader(make([]byte, 16))

	result, err := service.BeginLogin(context.Background())
	if err != nil {
		t.Fatalf("begin passkey login: %v", err)
	}
	if !bytes.Equal(result.Options, engine.loginOptions) {
		t.Fatalf("login options = %s", result.Options)
	}
	if store.challenge.Purpose != PasskeyChallengeLogin ||
		store.challenge.AccountID != "" || store.challenge.SessionID != "" {
		t.Fatalf("stored login challenge = %#v", store.challenge)
	}
}

func TestPasskeyLoginResolvesStableCredentialAndUpdatesCounter(t *testing.T) {
	user := PasskeyUser{
		AccountID: "88888888-8888-4888-8888-888888888888",
		VaultID:   "99999999-9999-4999-8999-999999999999",
		Handle:    bytes.Repeat([]byte{3}, 32),
		Name:      "discoverable_user",
	}
	credential := PasskeyCredential{
		ID:        []byte("discoverable-credential"),
		Record:    []byte(`{"id":"discoverable-credential","signCount":2}`),
		SignCount: 2,
	}
	store := &stubPasskeyStore{
		user:                user,
		consumedSessionData: []byte(`{"challenge":"stored-login"}`),
	}
	engine := &stubPasskeyEngine{
		loginUser:      user,
		credential:     credential,
		resolvedRawID:  credential.ID,
		resolvedHandle: user.Handle,
	}
	service, err := NewPasskeyService(stubRecentSessionAuthenticator{}, store, engine)
	if err != nil {
		t.Fatalf("create passkey service: %v", err)
	}
	service.now = func() time.Time {
		return time.Date(2026, time.July, 14, 13, 30, 0, 0, time.UTC)
	}

	result, err := service.CompleteLogin(context.Background(), PasskeyLoginCommand{
		ChallengeID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
		Response:    json.RawMessage(`{"id":"assertion-response"}`),
	})
	if err != nil {
		t.Fatalf("complete passkey login: %v", err)
	}
	if result.AccountID != user.AccountID || result.VaultID != user.VaultID {
		t.Fatalf("passkey login result = %#v", result)
	}
	if !bytes.Equal(store.lookupCredentialID, credential.ID) ||
		!bytes.Equal(store.lookupUserHandle, user.Handle) {
		t.Fatal("passkey user was not resolved by credential ID and user handle")
	}
	if !bytes.Equal(store.updatedCredential.ID, credential.ID) {
		t.Fatalf("updated credential = %#v", store.updatedCredential)
	}
}

type stubPasskeyEngine struct {
	registrationOptions json.RawMessage
	sessionData         []byte
	credential          PasskeyCredential
	loginOptions        json.RawMessage
	loginSessionData    []byte
	loginUser           PasskeyUser
	resolvedRawID       []byte
	resolvedHandle      []byte
}

func (engine *stubPasskeyEngine) BeginLogin() (json.RawMessage, []byte, error) {
	return engine.loginOptions, engine.loginSessionData, nil
}

func (engine *stubPasskeyEngine) FinishLogin(
	_ []byte,
	_ json.RawMessage,
	resolver PasskeyUserResolver,
) (PasskeyUser, PasskeyCredential, error) {
	if _, err := resolver(engine.resolvedRawID, engine.resolvedHandle); err != nil {
		return PasskeyUser{}, PasskeyCredential{}, err
	}
	return engine.loginUser, engine.credential, nil
}

func (engine *stubPasskeyEngine) FinishRegistration(
	PasskeyUser,
	[]byte,
	json.RawMessage,
) (PasskeyCredential, error) {
	return engine.credential, nil
}

func (engine *stubPasskeyEngine) BeginRegistration(
	PasskeyUser,
) (json.RawMessage, []byte, error) {
	return engine.registrationOptions, engine.sessionData, nil
}

type stubPasskeyStore struct {
	user                PasskeyUser
	challenge           PasskeyChallengeRecord
	consumed            ConsumePasskeyChallenge
	consumedSessionData []byte
	savedCredential     PasskeyCredential
	lookupCredentialID  []byte
	lookupUserHandle    []byte
	updatedCredential   PasskeyCredential
	saveCalls           int
}

func (store *stubPasskeyStore) ConsumeChallenge(
	_ context.Context,
	challenge ConsumePasskeyChallenge,
) ([]byte, error) {
	store.consumed = challenge
	return store.consumedSessionData, nil
}

func (store *stubPasskeyStore) SaveCredential(
	_ context.Context,
	_ string,
	credential PasskeyCredential,
) error {
	store.saveCalls++
	store.savedCredential = credential
	return nil
}

func (store *stubPasskeyStore) FindUserByCredential(
	_ context.Context,
	credentialID []byte,
	userHandle []byte,
) (PasskeyUser, error) {
	store.lookupCredentialID = append([]byte(nil), credentialID...)
	store.lookupUserHandle = append([]byte(nil), userHandle...)
	return store.user, nil
}

func (store *stubPasskeyStore) UpdateCredential(
	_ context.Context,
	_ string,
	credential PasskeyCredential,
) error {
	store.updatedCredential = credential
	return nil
}

func (store *stubPasskeyStore) EnsureUser(context.Context, string) (PasskeyUser, error) {
	return store.user, nil
}

func (store *stubPasskeyStore) CreateChallenge(
	_ context.Context,
	challenge PasskeyChallengeRecord,
) error {
	store.challenge = challenge
	return nil
}
