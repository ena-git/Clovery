package main

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/clovery/clovery/services/api/internal/billing"
	"github.com/clovery/clovery/services/api/internal/config"
	_ "github.com/jackc/pgx/v5/stdlib"
)

func replayNotificationHistory(ctx context.Context, options replayOptions) (int, error) {
	applicationConfig, err := config.Load()
	if err != nil {
		return 0, err
	}
	if !applicationConfig.AppleIAP.Enabled() {
		return 0, fmt.Errorf("Apple IAP configuration is required")
	}
	databaseHandle, err := sql.Open("pgx", applicationConfig.DatabaseURL)
	if err != nil {
		return 0, fmt.Errorf("open notification replay database: %w", err)
	}
	defer databaseHandle.Close()
	if err := databaseHandle.PingContext(ctx); err != nil {
		return 0, fmt.Errorf("ping notification replay database: %w", err)
	}
	appleConfig := applicationConfig.AppleIAP
	verifier, err := billing.NewAppleVerifier(billing.AppleVerifierConfig{
		IssuerID: appleConfig.IssuerID, KeyID: appleConfig.KeyID,
		PrivateKey: appleConfig.PrivateKey, BundleID: appleConfig.BundleID,
		AppAppleID: appleConfig.AppAppleID, RootCA: appleConfig.RootCA,
		ProductIDs: appleConfig.ProductIDs, AllowSandbox: appleConfig.AllowSandbox,
	})
	if err != nil {
		return 0, err
	}
	service, err := billing.NewService(verifier, billing.NewPostgresRepository(databaseHandle))
	if err != nil {
		return 0, err
	}
	return service.ReplayNotificationHistory(ctx, options.query)
}
