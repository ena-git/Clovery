package auth

import (
	"context"
	"fmt"
	"strings"

	"golang.org/x/oauth2"
)

type OIDCClientSecretSource interface {
	ClientSecret(ctx context.Context) (string, error)
}

type StaticOIDCClientSecret string

func (secret StaticOIDCClientSecret) ClientSecret(context.Context) (string, error) {
	value := strings.TrimSpace(string(secret))
	if value == "" {
		return "", fmt.Errorf("OIDC client secret is required")
	}
	return value, nil
}

type oauthAuthorizationCodeExchanger struct {
	config       oauth2.Config
	clientSecret OIDCClientSecretSource
}

func (exchanger oauthAuthorizationCodeExchanger) Exchange(
	ctx context.Context,
	authorizationCode string,
) (string, error) {
	clientSecret, err := exchanger.clientSecret.ClientSecret(ctx)
	if err != nil {
		return "", err
	}
	config := exchanger.config
	config.ClientSecret = clientSecret
	token, err := config.Exchange(ctx, authorizationCode)
	if err != nil {
		return "", fmt.Errorf("exchange OIDC authorization code: %w", err)
	}
	rawIDToken, ok := token.Extra("id_token").(string)
	if !ok || strings.TrimSpace(rawIDToken) == "" {
		return "", fmt.Errorf("OIDC token response did not contain an ID token")
	}
	return rawIDToken, nil
}
