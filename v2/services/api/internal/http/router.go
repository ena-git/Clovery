package httpapi

import (
	"net/http"

	"github.com/clovery/clovery/services/api/internal/observability"
	"github.com/go-chi/chi/v5"
)

type RouterDependencies struct {
	Auth                   AuthApplication
	Sessions               HTTPSessionService
	Federation             FederatedHTTPApplication
	Passkeys               PasskeyHTTPApplication
	Account                AccountHTTPApplication
	Devices                DeviceHTTPApplication
	Vault                  VaultHTTPApplication
	Sync                   SyncHTTPApplication
	Assets                 AssetHTTPApplication
	Migrations             MigrationHTTPApplication
	Billing                BillingHTTPApplication
	Metrics                *observability.Registry
	MetricsBearerToken     string
	MigrationWritesEnabled bool
}

func NewRouter(dependencies ...RouterDependencies) http.Handler {
	router := chi.NewRouter()
	if len(dependencies) > 0 && dependencies[0].Metrics != nil {
		router.Use(operationalMetricsMiddleware(dependencies[0].Metrics))
	}
	router.Get("/v1/health", healthHandler)
	if len(dependencies) > 0 && dependencies[0].Metrics != nil && dependencies[0].MetricsBearerToken != "" {
		router.Handle("/internal/metrics", dependencies[0].Metrics.ProtectedHandler(dependencies[0].MetricsBearerToken))
	}
	if len(dependencies) > 0 && dependencies[0].Auth != nil {
		registerAuthRoutes(router, dependencies[0].Auth)
	}
	if len(dependencies) > 0 && dependencies[0].Sessions != nil {
		registerSessionRoutes(router, dependencies[0].Sessions)
	}
	if len(dependencies) > 0 && dependencies[0].Federation != nil && dependencies[0].Sessions != nil {
		registerFederationRoutes(router, dependencies[0].Federation, dependencies[0].Sessions)
	}
	if len(dependencies) > 0 && dependencies[0].Passkeys != nil && dependencies[0].Sessions != nil {
		registerPasskeyRoutes(router, dependencies[0].Passkeys, dependencies[0].Sessions)
	}
	if len(dependencies) > 0 && dependencies[0].Account != nil && dependencies[0].Sessions != nil {
		registerAccountRoutes(router, dependencies[0].Account, dependencies[0].Sessions)
	}
	if len(dependencies) > 0 && dependencies[0].Devices != nil && dependencies[0].Sessions != nil {
		registerDeviceRoutes(router, dependencies[0].Devices, dependencies[0].Sessions)
	}
	if len(dependencies) > 0 && dependencies[0].Vault != nil && dependencies[0].Sessions != nil {
		registerVaultRoutes(router, dependencies[0].Vault, dependencies[0].Sessions)
	}
	if len(dependencies) > 0 && dependencies[0].Sync != nil && dependencies[0].Sessions != nil {
		registerSyncRoutes(router, dependencies[0].Sync, dependencies[0].Sessions, dependencies[0].Metrics)
	}
	if len(dependencies) > 0 && dependencies[0].Assets != nil && dependencies[0].Sessions != nil {
		registerAssetRoutes(router, dependencies[0].Assets, dependencies[0].Sessions)
	}
	if len(dependencies) > 0 && dependencies[0].Migrations != nil && dependencies[0].Sessions != nil {
		registerMigrationRoutes(
			router, dependencies[0].Migrations, dependencies[0].Sessions,
			dependencies[0].MigrationWritesEnabled,
		)
	}
	if len(dependencies) > 0 && dependencies[0].Billing != nil && dependencies[0].Sessions != nil {
		registerBillingRoutes(router, dependencies[0].Billing, dependencies[0].Sessions)
	}
	return router
}
