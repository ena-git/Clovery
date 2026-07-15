package main

import (
	"database/sql"

	httpapi "github.com/clovery/clovery/services/api/internal/http"
	cloverysync "github.com/clovery/clovery/services/api/internal/sync"
	"github.com/clovery/clovery/services/api/internal/vault"
)

func buildSyncApplication(databaseHandle *sql.DB) (httpapi.SyncHTTPApplication, error) {
	vaults, err := vault.NewService(vault.NewPostgresRepository(databaseHandle))
	if err != nil {
		return nil, err
	}
	return cloverysync.NewService(vaults, cloverysync.NewPostgresRepository(databaseHandle))
}
