package main

import (
	"database/sql"

	"github.com/clovery/clovery/services/api/internal/asset"
	httpapi "github.com/clovery/clovery/services/api/internal/http"
	cloverymigration "github.com/clovery/clovery/services/api/internal/migration"
	"github.com/clovery/clovery/services/api/internal/vault"
)

func buildMigrationApplication(
	databaseHandle *sql.DB,
	assets *asset.Service,
) (httpapi.MigrationHTTPApplication, error) {
	vaults, err := vault.NewService(vault.NewPostgresRepository(databaseHandle))
	if err != nil {
		return nil, err
	}
	return cloverymigration.NewService(
		vaults,
		cloverymigration.NewPostgresRepository(databaseHandle),
		assets,
	)
}
