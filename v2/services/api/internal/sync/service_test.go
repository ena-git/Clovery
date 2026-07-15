package sync

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/clovery/clovery/services/api/internal/vault"
)

func TestServiceUsesAuthenticatedVaultForPushAndPull(t *testing.T) {
	authorizer := &stubVaultAuthorizer{}
	repository := &stubSyncRepository{
		decision: Decision{OperationID: "operation", Status: StatusApplied},
		changes:  []Change{{Cursor: 5}, {Cursor: 8}},
	}
	service, err := NewService(authorizer, repository)
	if err != nil {
		t.Fatalf("create sync service: %v", err)
	}

	results, err := service.Push(context.Background(), "account", "vault", []Operation{{
		OperationID: "operation", EntryID: "entry", Payload: []byte(`{"text":"hello"}`),
	}})
	if err != nil {
		t.Fatalf("Push() error = %v", err)
	}
	page, err := service.Pull(context.Background(), "account", "vault", 0, 1)
	if err != nil {
		t.Fatalf("Pull() error = %v", err)
	}
	if len(results) != 1 || repository.vaultID != "vault" || len(page.Changes) != 1 || !page.HasMore {
		t.Fatalf("results = %#v, page = %#v, repository vault = %q", results, page, repository.vaultID)
	}
	if authorizer.accountID != "account" || authorizer.vaultID != "vault" {
		t.Fatalf("authorization account = %q, vault = %q", authorizer.accountID, authorizer.vaultID)
	}
}

func TestServiceRejectsOversizedPushBatch(t *testing.T) {
	service, err := NewService(&stubVaultAuthorizer{}, &stubSyncRepository{})
	if err != nil {
		t.Fatalf("create sync service: %v", err)
	}
	operations := make([]Operation, maximumPushOperations+1)

	_, err = service.Push(context.Background(), "account", "vault", operations)
	if !errors.Is(err, ErrInvalidOperation) {
		t.Fatalf("oversized Push() error = %v", err)
	}
}

type stubVaultAuthorizer struct {
	accountID string
	vaultID   string
	err       error
}

func (stub *stubVaultAuthorizer) Get(
	_ context.Context,
	accountID string,
	vaultID string,
) (vault.Metadata, error) {
	stub.accountID = accountID
	stub.vaultID = vaultID
	return vault.Metadata{}, stub.err
}

type stubSyncRepository struct {
	vaultID  string
	decision Decision
	changes  []Change
}

func (stub *stubSyncRepository) Apply(
	_ context.Context,
	vaultID string,
	_ Operation,
	_ time.Time,
) (Decision, error) {
	stub.vaultID = vaultID
	return stub.decision, nil
}

func (stub *stubSyncRepository) ListChanges(
	_ context.Context,
	vaultID string,
	_ int64,
	_ int,
) ([]Change, error) {
	stub.vaultID = vaultID
	return stub.changes, nil
}
