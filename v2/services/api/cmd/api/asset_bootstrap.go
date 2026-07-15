package main

import (
	"database/sql"

	"github.com/clovery/clovery/services/api/internal/asset"
	"github.com/clovery/clovery/services/api/internal/config"
	"github.com/clovery/clovery/services/api/internal/vault"
)

func buildAssetApplication(
	databaseHandle *sql.DB,
	applicationConfig config.Config,
) (*asset.Service, error) {
	vaults, err := vault.NewService(vault.NewPostgresRepository(databaseHandle))
	if err != nil {
		return nil, err
	}
	objects, err := asset.NewMinIOObjectStore(
		applicationConfig.S3Endpoint,
		applicationConfig.S3Bucket,
		applicationConfig.S3AccessKey,
		applicationConfig.S3SecretKey,
		applicationConfig.S3AllowInsecure,
	)
	if err != nil {
		return nil, err
	}
	return asset.NewService(vaults, asset.NewPostgresRepository(databaseHandle), objects)
}
