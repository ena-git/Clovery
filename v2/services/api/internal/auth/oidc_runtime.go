package auth

import (
	"context"
	"fmt"
	"strings"

	"github.com/coreos/go-oidc/v3/oidc"
	"golang.org/x/oauth2"
)

type ProductionOIDCConfig struct {
	ClientID     string
	ClientSecret OIDCClientSecretSource
	RedirectURL  string
}

type oidcProviderMetadata struct {
	Name       string
	Issuer     string
	AuthURL    string
	TokenURL   string
	JWKSURL    string
	Algorithms []string
	AuthStyle  oauth2.AuthStyle
}

func newProductionOIDCIdentityProvider(
	ctx context.Context,
	metadata oidcProviderMetadata,
	config ProductionOIDCConfig,
) (IdentityProvider, error) {
	clientID := strings.TrimSpace(config.ClientID)
	redirectURL := strings.TrimSpace(config.RedirectURL)
	if clientID == "" || redirectURL == "" || config.ClientSecret == nil {
		return nil, fmt.Errorf("%s OIDC configuration is incomplete", metadata.Name)
	}
	provider := (&oidc.ProviderConfig{
		IssuerURL:  metadata.Issuer,
		AuthURL:    metadata.AuthURL,
		TokenURL:   metadata.TokenURL,
		JWKSURL:    metadata.JWKSURL,
		Algorithms: append([]string(nil), metadata.Algorithms...),
	}).NewProvider(ctx)
	endpoint := provider.Endpoint()
	endpoint.AuthStyle = metadata.AuthStyle
	exchanger := oauthAuthorizationCodeExchanger{
		config: oauth2.Config{
			ClientID:    clientID,
			RedirectURL: redirectURL,
			Endpoint:    endpoint,
			Scopes:      []string{"openid", "email"},
		},
		clientSecret: config.ClientSecret,
	}
	verifier := oidcTokenVerifier{
		verifier: provider.VerifierContext(ctx, &oidc.Config{ClientID: clientID}),
	}
	return NewOIDCIdentityProvider(metadata.Name, exchanger, verifier)
}

type oidcTokenVerifier struct {
	verifier *oidc.IDTokenVerifier
}

func (verifier oidcTokenVerifier) Verify(
	ctx context.Context,
	rawIDToken string,
) (OIDCClaims, error) {
	idToken, err := verifier.verifier.Verify(ctx, rawIDToken)
	if err != nil {
		return OIDCClaims{}, err
	}
	var claims struct {
		Email string `json:"email"`
		Nonce string `json:"nonce"`
	}
	if err := idToken.Claims(&claims); err != nil {
		return OIDCClaims{}, err
	}
	return OIDCClaims{
		Issuer:  idToken.Issuer,
		Subject: idToken.Subject,
		Email:   claims.Email,
		Nonce:   claims.Nonce,
	}, nil
}
