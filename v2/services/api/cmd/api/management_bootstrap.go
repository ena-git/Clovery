package main

import (
	"database/sql"

	"github.com/clovery/clovery/services/api/internal/account"
	"github.com/clovery/clovery/services/api/internal/auth"
	"github.com/clovery/clovery/services/api/internal/device"
	httpapi "github.com/clovery/clovery/services/api/internal/http"
	"github.com/clovery/clovery/services/api/internal/vault"
)

func buildManagementApplications(
	databaseHandle *sql.DB,
	sessions *auth.SessionService,
) (httpapi.AccountHTTPApplication, httpapi.DeviceHTTPApplication, httpapi.VaultHTTPApplication, error) {
	accounts := account.NewRepository(databaseHandle)
	deletions, err := account.NewDeletionService(accounts)
	if err != nil {
		return nil, nil, nil, err
	}
	devices, err := device.NewService(device.NewPostgresRepository(databaseHandle), sessions)
	if err != nil {
		return nil, nil, nil, err
	}
	vaults, err := vault.NewService(vault.NewPostgresRepository(databaseHandle))
	if err != nil {
		return nil, nil, nil, err
	}
	return httpapi.NewAccountApplication(accounts, deletions),
		httpapi.NewDeviceApplication(devices),
		httpapi.NewVaultApplication(vaults),
		nil
}
