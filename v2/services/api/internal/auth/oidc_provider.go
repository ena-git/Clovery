package auth

import (
	"context"
	"crypto/hmac"
	"fmt"
	"strings"
)

type OIDCClaims struct {
	Issuer  string
	Subject string
	Email   string
	Nonce   string
}

type AuthorizationCodeExchanger interface {
	Exchange(ctx context.Context, authorizationCode string) (idToken string, err error)
}

type IDTokenVerifier interface {
	Verify(ctx context.Context, rawIDToken string) (OIDCClaims, error)
}

type OIDCIdentityProvider struct {
	name      string
	exchanger AuthorizationCodeExchanger
	verifier  IDTokenVerifier
}

func NewOIDCIdentityProvider(
	name string,
	exchanger AuthorizationCodeExchanger,
	verifier IDTokenVerifier,
) (*OIDCIdentityProvider, error) {
	name = strings.ToLower(strings.TrimSpace(name))
	if name == "" || exchanger == nil || verifier == nil {
		return nil, fmt.Errorf("OIDC identity provider dependencies are required")
	}
	return &OIDCIdentityProvider{name: name, exchanger: exchanger, verifier: verifier}, nil
}

func (provider *OIDCIdentityProvider) Name() string {
	return provider.name
}

func (provider *OIDCIdentityProvider) Verify(
	ctx context.Context,
	authorizationCode string,
	nonce string,
) (VerifiedIdentity, error) {
	authorizationCode = strings.TrimSpace(authorizationCode)
	nonce = strings.TrimSpace(nonce)
	if authorizationCode == "" || nonce == "" {
		return VerifiedIdentity{}, ErrFederatedAuthentication
	}
	rawIDToken, err := provider.exchanger.Exchange(ctx, authorizationCode)
	if err != nil || strings.TrimSpace(rawIDToken) == "" {
		return VerifiedIdentity{}, ErrFederatedAuthentication
	}
	claims, err := provider.verifier.Verify(ctx, rawIDToken)
	if err != nil {
		return VerifiedIdentity{}, ErrFederatedAuthentication
	}
	issuer := strings.TrimSpace(claims.Issuer)
	subject := strings.TrimSpace(claims.Subject)
	if issuer == "" || subject == "" ||
		!hmac.Equal([]byte(nonce), []byte(strings.TrimSpace(claims.Nonce))) {
		return VerifiedIdentity{}, ErrFederatedAuthentication
	}
	return VerifiedIdentity{
		Issuer:  issuer,
		Subject: subject,
		Email:   strings.TrimSpace(claims.Email),
	}, nil
}
