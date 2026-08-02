package main

import (
	"context"
	"database/sql"

	"github.com/clovery/clovery/services/api/internal/application/identityflow"
	"github.com/clovery/clovery/services/api/internal/auth"
	"github.com/clovery/clovery/services/api/internal/config"
	httpapi "github.com/clovery/clovery/services/api/internal/http"
)

type federatedFlowBuilder func(
	*auth.FederationService,
	*auth.SessionService,
	identityflow.IdentityClaimIssuer,
) (*identityflow.FederatedFlow, error)

func buildIdentityApplications(
	databaseHandle *sql.DB,
	sessions *auth.SessionService,
	claims identityflow.IdentityClaimIssuer,
	applicationConfig config.Config,
) (httpapi.FederatedHTTPApplication, httpapi.PasskeyHTTPApplication, error) {
	return buildIdentityApplicationsWithFederatedFlowBuilder(
		databaseHandle,
		sessions,
		claims,
		applicationConfig,
		func(
			federation *auth.FederationService,
			sessions *auth.SessionService,
			claims identityflow.IdentityClaimIssuer,
		) (*identityflow.FederatedFlow, error) {
			return identityflow.NewFederatedFlow(federation, sessions, claims)
		},
	)
}

func buildIdentityApplicationsWithFederatedFlowBuilder(
	databaseHandle *sql.DB,
	sessions *auth.SessionService,
	claims identityflow.IdentityClaimIssuer,
	applicationConfig config.Config,
	buildFederatedFlow federatedFlowBuilder,
) (httpapi.FederatedHTTPApplication, httpapi.PasskeyHTTPApplication, error) {
	providers, err := buildOIDCProviders(context.Background(), applicationConfig)
	if err != nil {
		return nil, nil, err
	}
	federation, err := auth.NewFederationService(
		sessions,
		auth.NewPostgresFederationStore(databaseHandle),
		providers,
	)
	if err != nil {
		return nil, nil, err
	}
	federatedFlow, err := buildFederatedFlow(federation, sessions, claims)
	if err != nil {
		return nil, nil, err
	}

	passkeys, err := buildPasskeyService(databaseHandle, sessions, applicationConfig)
	if err != nil {
		return nil, nil, err
	}
	passkeyFlow, err := identityflow.NewPasskeyFlow(passkeys, sessions)
	if err != nil {
		return nil, nil, err
	}
	return httpapi.NewFederatedApplication(federatedFlow), httpapi.NewPasskeyApplication(passkeyFlow), nil
}

func buildPasskeyService(
	databaseHandle *sql.DB,
	sessions *auth.SessionService,
	applicationConfig config.Config,
) (*auth.PasskeyService, error) {
	cipher, err := auth.NewPasskeyCredentialCipher(applicationConfig.PasskeyCredentialEncryptionKey)
	if err != nil {
		return nil, err
	}
	engine, err := auth.NewWebAuthnEngine(auth.WebAuthnConfig{
		RelyingPartyID:          applicationConfig.WebAuthnRPID,
		RelyingPartyDisplayName: applicationConfig.WebAuthnRPDisplayName,
		Origins:                 applicationConfig.WebAuthnOrigins,
	})
	if err != nil {
		return nil, err
	}
	return auth.NewPasskeyService(
		sessions,
		auth.NewPostgresPasskeyStore(databaseHandle, cipher),
		engine,
	)
}
