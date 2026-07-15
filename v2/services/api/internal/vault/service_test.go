package vault

import (
	"context"
	"errors"
	"testing"
)

func TestGetRejectsCrossAccountVaultAndAuditsDenial(t *testing.T) {
	repository := &stubRepository{getErr: ErrForbidden}
	service, err := NewService(repository)
	if err != nil {
		t.Fatalf("create vault service: %v", err)
	}

	_, err = service.Get(
		context.Background(),
		"11111111-1111-4111-8111-111111111111",
		"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
	)
	if !errors.Is(err, ErrForbidden) {
		t.Fatalf("cross-account vault error = %v", err)
	}
	if repository.auditedAccountID != "11111111-1111-4111-8111-111111111111" ||
		repository.auditedVaultID != "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" {
		t.Fatalf("audit account = %q, vault = %q", repository.auditedAccountID, repository.auditedVaultID)
	}
}

type stubRepository struct {
	metadata         Metadata
	getErr           error
	auditedAccountID string
	auditedVaultID   string
}

func (repository *stubRepository) GetOwned(
	context.Context,
	string,
	string,
) (Metadata, error) {
	return repository.metadata, repository.getErr
}

func (repository *stubRepository) RecordAccessDenial(
	_ context.Context,
	accountID string,
	vaultID string,
) error {
	repository.auditedAccountID = accountID
	repository.auditedVaultID = vaultID
	return nil
}
