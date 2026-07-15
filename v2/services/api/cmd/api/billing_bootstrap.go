package main

import (
	"database/sql"

	"github.com/clovery/clovery/services/api/internal/billing"
	"github.com/clovery/clovery/services/api/internal/config"
	httpapi "github.com/clovery/clovery/services/api/internal/http"
)

func buildBillingApplication(
	databaseHandle *sql.DB,
	applicationConfig config.Config,
) (httpapi.BillingHTTPApplication, error) {
	if !applicationConfig.AppleIAP.Enabled() {
		return nil, nil
	}
	appleConfig := applicationConfig.AppleIAP
	verifier, err := billing.NewAppleVerifier(billing.AppleVerifierConfig{
		IssuerID: appleConfig.IssuerID, KeyID: appleConfig.KeyID,
		PrivateKey: appleConfig.PrivateKey, BundleID: appleConfig.BundleID,
		AppAppleID: appleConfig.AppAppleID,
		RootCA:     appleConfig.RootCA, ProductIDs: appleConfig.ProductIDs,
		AllowSandbox: appleConfig.AllowSandbox,
	})
	if err != nil {
		return nil, err
	}
	return billing.NewService(verifier, billing.NewPostgresRepository(databaseHandle))
}
