package main

import (
	"context"
	"database/sql"
	"fmt"
	"net/http"

	"github.com/clovery/clovery/services/api/internal/application/authflow"
	"github.com/clovery/clovery/services/api/internal/auth"
	"github.com/clovery/clovery/services/api/internal/config"
	httpapi "github.com/clovery/clovery/services/api/internal/http"
	"github.com/clovery/clovery/services/api/internal/identityclaim"
	"github.com/clovery/clovery/services/api/internal/observability"
	_ "github.com/jackc/pgx/v5/stdlib"
)

func openApplicationDatabase(ctx context.Context, databaseURL string) (*sql.DB, error) {
	databaseHandle, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return nil, fmt.Errorf("open application database: %w", err)
	}
	if err := databaseHandle.PingContext(ctx); err != nil {
		_ = databaseHandle.Close()
		return nil, fmt.Errorf("ping application database: %w", err)
	}
	return databaseHandle, nil
}

func buildHandler(databaseHandle *sql.DB, applicationConfig config.Config) (http.Handler, error) {
	signer, err := auth.NewAccessTokenSigner(
		applicationConfig.JWTIssuer,
		[]byte(applicationConfig.JWTSigningKey),
	)
	if err != nil {
		return nil, err
	}
	sessions := auth.NewSessionService(databaseHandle, signer)
	claimRepository := identityclaim.NewPostgresRepository(databaseHandle)
	claims := identityclaim.NewService(claimRepository)
	authService, err := authflow.NewServiceWithSessions(databaseHandle, sessions)
	if err != nil {
		return nil, err
	}
	federation, passkeys, err := buildIdentityApplications(databaseHandle, sessions, claims, applicationConfig)
	if err != nil {
		return nil, err
	}
	accounts, devices, vaults, err := buildManagementApplications(databaseHandle, sessions)
	if err != nil {
		return nil, err
	}
	syncApplication, err := buildSyncApplication(databaseHandle)
	if err != nil {
		return nil, err
	}
	assetApplication, err := buildAssetApplication(databaseHandle, applicationConfig)
	if err != nil {
		return nil, err
	}
	migrationApplication, err := buildMigrationApplication(databaseHandle, assetApplication)
	if err != nil {
		return nil, err
	}
	billingApplication, err := buildBillingApplication(databaseHandle, applicationConfig)
	if err != nil {
		return nil, err
	}
	metrics := observability.NewRegistry()
	return httpapi.NewRouter(httpapi.RouterDependencies{
		Auth:                   httpapi.NewAuthApplication(authService),
		Sessions:               authService,
		Federation:             federation,
		Passkeys:               passkeys,
		Account:                accounts,
		Devices:                devices,
		Vault:                  vaults,
		Sync:                   syncApplication,
		Assets:                 assetApplication,
		Migrations:             migrationApplication,
		Billing:                billingApplication,
		Metrics:                metrics,
		MetricsBearerToken:     applicationConfig.MetricsBearerToken,
		MigrationWritesEnabled: applicationConfig.MigrationWritesEnabled,
	}), nil
}
