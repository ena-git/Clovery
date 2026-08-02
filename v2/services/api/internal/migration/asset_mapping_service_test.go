package migration

import (
	"context"
	"errors"
	"testing"

	"github.com/clovery/clovery/services/api/internal/vault"
)

func TestAssetsAuthorizesVaultBeforeReturningMappings(t *testing.T) {
	store := &stubMigrationStore{assetMappings: []AssetMapping{{SourceFilename: "photo-0001.jpg"}}}
	service, err := NewService(&stubMigrationVaults{}, store)
	if err != nil {
		t.Fatalf("NewService() error = %v", err)
	}

	mappings, err := service.Assets(
		context.Background(), "account", "vault", "11111111-1111-4111-8111-111111111111",
	)
	if err != nil || len(mappings) != 1 || !store.assetsRequested {
		t.Fatalf("Assets() = %#v, requested = %t, error = %v", mappings, store.assetsRequested, err)
	}
}

func TestAssetsDoesNotQueryMappingsWhenVaultAccessIsDenied(t *testing.T) {
	store := &stubMigrationStore{}
	service, err := NewService(deniedMigrationVaults{}, store)
	if err != nil {
		t.Fatalf("NewService() error = %v", err)
	}

	_, err = service.Assets(
		context.Background(), "other-account", "vault", "11111111-1111-4111-8111-111111111111",
	)
	if !errors.Is(err, vault.ErrForbidden) || store.assetsRequested {
		t.Fatalf("Assets() requested = %t, error = %v", store.assetsRequested, err)
	}
}
