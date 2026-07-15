package auth

import (
	"context"
	"errors"
	"fmt"
	"strings"
)

var ErrIdentityProviderDisabled = errors.New("identity provider is disabled")

type DisabledIdentityProvider struct {
	name string
}

func NewDisabledIdentityProvider(name string) (*DisabledIdentityProvider, error) {
	name = strings.ToLower(strings.TrimSpace(name))
	if name != "wechat" && name != "qq" {
		return nil, fmt.Errorf("unsupported disabled identity provider")
	}
	return &DisabledIdentityProvider{name: name}, nil
}

func (provider *DisabledIdentityProvider) Name() string {
	return provider.name
}

func (*DisabledIdentityProvider) Verify(
	context.Context,
	string,
	string,
) (VerifiedIdentity, error) {
	return VerifiedIdentity{}, ErrIdentityProviderDisabled
}
