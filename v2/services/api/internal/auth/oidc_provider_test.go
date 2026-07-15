package auth

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"golang.org/x/oauth2"
)

func TestOIDCIdentityProviderRejectsNonceMismatch(t *testing.T) {
	provider, err := NewOIDCIdentityProvider(
		"apple",
		stubAuthorizationCodeExchanger{idToken: "signed-id-token"},
		stubIDTokenVerifier{claims: OIDCClaims{
			Issuer:  "https://appleid.apple.com",
			Subject: "stable-apple-subject",
			Email:   "hidden@privaterelay.appleid.com",
			Nonce:   "different-nonce",
		}},
	)
	if err != nil {
		t.Fatalf("create OIDC provider: %v", err)
	}

	_, err = provider.Verify(context.Background(), "authorization-code", "expected-nonce")
	if !errors.Is(err, ErrFederatedAuthentication) {
		t.Fatalf("nonce mismatch error = %v", err)
	}
}

func TestOIDCAuthorizationCodeExchangeRequiresIDToken(t *testing.T) {
	tokenServer := httptest.NewServer(http.HandlerFunc(func(responseWriter http.ResponseWriter, request *http.Request) {
		responseWriter.Header().Set("Content-Type", "application/json")
		_, _ = responseWriter.Write([]byte(`{"access_token":"access-only","token_type":"Bearer"}`))
	}))
	t.Cleanup(tokenServer.Close)
	exchanger := oauthAuthorizationCodeExchanger{
		config: oauth2.Config{
			ClientID:    "client-id",
			RedirectURL: "https://accounts.clovery.example/callback",
			Endpoint:    oauth2.Endpoint{TokenURL: tokenServer.URL},
		},
		clientSecret: StaticOIDCClientSecret("client-secret"),
	}

	if _, err := exchanger.Exchange(context.Background(), "authorization-code"); err == nil {
		t.Fatal("authorization code exchange accepted response without ID token")
	}
}

func TestProductionOIDCAdaptersUseCanonicalProviderNames(t *testing.T) {
	config := ProductionOIDCConfig{
		ClientID:     "client-id",
		ClientSecret: StaticOIDCClientSecret("client-secret"),
		RedirectURL:  "https://accounts.clovery.example/callback",
	}
	constructors := []struct {
		name string
		new  func(context.Context, ProductionOIDCConfig) (IdentityProvider, error)
	}{
		{name: "apple", new: NewAppleIdentityProvider},
		{name: "google", new: NewGoogleIdentityProvider},
		{name: "huawei", new: NewHuaweiIdentityProvider},
	}

	for _, constructor := range constructors {
		t.Run(constructor.name, func(t *testing.T) {
			provider, err := constructor.new(context.Background(), config)
			if err != nil {
				t.Fatalf("create %s provider: %v", constructor.name, err)
			}
			if provider.Name() != constructor.name {
				t.Fatalf("provider name = %q", provider.Name())
			}
		})
	}
}

func TestDisabledChineseSocialProviderNeverVerifiesClientIdentity(t *testing.T) {
	provider, err := NewDisabledIdentityProvider("wechat")
	if err != nil {
		t.Fatalf("create disabled identity provider: %v", err)
	}

	_, err = provider.Verify(context.Background(), "client-openid", "nonce")
	if !errors.Is(err, ErrIdentityProviderDisabled) {
		t.Fatalf("disabled provider verification error = %v", err)
	}
}

type stubAuthorizationCodeExchanger struct {
	idToken string
	err     error
}

func (stub stubAuthorizationCodeExchanger) Exchange(
	context.Context,
	string,
) (string, error) {
	return stub.idToken, stub.err
}

type stubIDTokenVerifier struct {
	claims OIDCClaims
	err    error
}

func (stub stubIDTokenVerifier) Verify(
	context.Context,
	string,
) (OIDCClaims, error) {
	return stub.claims, stub.err
}
