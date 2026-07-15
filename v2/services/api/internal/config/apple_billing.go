package config

import (
	"encoding/base64"
	"fmt"
	"os"
	"strconv"
	"strings"
)

type AppleBillingConfig struct {
	IssuerID     string
	KeyID        string
	PrivateKey   []byte
	BundleID     string
	AppAppleID   int64
	RootCA       []byte
	ProductIDs   []string
	AllowSandbox bool
}

func (config AppleBillingConfig) Enabled() bool {
	return config.IssuerID != "" && config.KeyID != "" && len(config.PrivateKey) > 0 &&
		config.BundleID != "" && config.AppAppleID > 0 && len(config.RootCA) > 0 &&
		len(config.ProductIDs) > 0
}

func loadAppleBillingConfig(environment DeploymentEnvironment) (AppleBillingConfig, error) {
	values := map[string]string{}
	for _, key := range []string{
		"APPLE_IAP_ISSUER_ID",
		"APPLE_IAP_KEY_ID",
		"APPLE_IAP_PRIVATE_KEY_BASE64",
		"APPLE_IAP_BUNDLE_ID",
		"APPLE_IAP_APP_APPLE_ID",
		"APPLE_IAP_ROOT_CA_BASE64",
		"APPLE_IAP_PRODUCT_IDS",
	} {
		values[key] = strings.TrimSpace(os.Getenv(key))
	}
	configured := 0
	for _, value := range values {
		if value != "" {
			configured++
		}
	}
	if configured == 0 {
		if environment == DeploymentProduction {
			return AppleBillingConfig{}, fmt.Errorf("APPLE_IAP configuration is required in production")
		}
		return AppleBillingConfig{}, nil
	}
	if configured != len(values) {
		return AppleBillingConfig{}, fmt.Errorf("APPLE_IAP configuration is incomplete")
	}

	privateKey, err := decodeAppleBillingBase64("APPLE_IAP_PRIVATE_KEY_BASE64", values)
	if err != nil {
		return AppleBillingConfig{}, err
	}
	rootCA, err := decodeAppleBillingBase64("APPLE_IAP_ROOT_CA_BASE64", values)
	if err != nil {
		return AppleBillingConfig{}, err
	}
	productIDs := splitConfigurationList(values["APPLE_IAP_PRODUCT_IDS"])
	if len(productIDs) == 0 {
		return AppleBillingConfig{}, fmt.Errorf("APPLE_IAP_PRODUCT_IDS must contain at least one product")
	}
	appAppleID, err := strconv.ParseInt(values["APPLE_IAP_APP_APPLE_ID"], 10, 64)
	if err != nil || appAppleID <= 0 {
		return AppleBillingConfig{}, fmt.Errorf("APPLE_IAP_APP_APPLE_ID must be a positive integer")
	}
	allowSandbox := false
	if raw := strings.TrimSpace(os.Getenv("APPLE_IAP_ALLOW_SANDBOX")); raw != "" {
		allowSandbox, err = strconv.ParseBool(raw)
		if err != nil {
			return AppleBillingConfig{}, fmt.Errorf("APPLE_IAP_ALLOW_SANDBOX must be true or false")
		}
	}
	if environment == DeploymentProduction && allowSandbox {
		return AppleBillingConfig{}, fmt.Errorf("APPLE_IAP_ALLOW_SANDBOX must be false in production")
	}
	return AppleBillingConfig{
		IssuerID: values["APPLE_IAP_ISSUER_ID"], KeyID: values["APPLE_IAP_KEY_ID"],
		PrivateKey: privateKey, BundleID: values["APPLE_IAP_BUNDLE_ID"], AppAppleID: appAppleID,
		RootCA: rootCA, ProductIDs: productIDs, AllowSandbox: allowSandbox,
	}, nil
}

func decodeAppleBillingBase64(key string, values map[string]string) ([]byte, error) {
	decoded, err := base64.StdEncoding.DecodeString(values[key])
	if err != nil || len(decoded) == 0 {
		return nil, fmt.Errorf("%s must contain non-empty base64 data", key)
	}
	return decoded, nil
}
