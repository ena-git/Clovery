package billing

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"net/http"
	"strings"
	"time"
)

const (
	appleProductionBaseURL = "https://api.storekit.apple.com"
	appleSandboxBaseURL    = "https://api.storekit-sandbox.apple.com"
)

type HTTPDoer interface {
	Do(request *http.Request) (*http.Response, error)
}

type AppleVerifierConfig struct {
	IssuerID          string
	KeyID             string
	PrivateKey        []byte
	BundleID          string
	AppAppleID        int64
	RootCA            []byte
	ProductIDs        []string
	AllowSandbox      bool
	HTTPClient        HTTPDoer
	ProductionBaseURL string
	SandboxBaseURL    string
	Now               func() time.Time
}

type AppleVerifier struct {
	issuerID          string
	keyID             string
	privateKey        *ecdsa.PrivateKey
	bundleID          string
	appAppleID        int64
	roots             *x509.CertPool
	productIDs        map[string]struct{}
	allowSandbox      bool
	httpClient        HTTPDoer
	productionBaseURL string
	sandboxBaseURL    string
	now               func() time.Time
}

func NewAppleVerifier(config AppleVerifierConfig) (*AppleVerifier, error) {
	if strings.TrimSpace(config.IssuerID) == "" || strings.TrimSpace(config.KeyID) == "" ||
		strings.TrimSpace(config.BundleID) == "" || config.AppAppleID <= 0 || len(config.ProductIDs) == 0 {
		return nil, fmt.Errorf("complete Apple verifier configuration is required")
	}
	privateKey, err := parseApplePrivateKey(config.PrivateKey)
	if err != nil {
		return nil, err
	}
	roots, err := parseAppleRoots(config.RootCA)
	if err != nil {
		return nil, err
	}
	products := make(map[string]struct{}, len(config.ProductIDs))
	for _, productID := range config.ProductIDs {
		productID = strings.TrimSpace(productID)
		if productID == "" {
			return nil, fmt.Errorf("Apple product IDs must not be empty")
		}
		products[productID] = struct{}{}
	}
	if config.HTTPClient == nil {
		config.HTTPClient = &http.Client{Timeout: 10 * time.Second}
	}
	if config.ProductionBaseURL == "" {
		config.ProductionBaseURL = appleProductionBaseURL
	}
	if config.SandboxBaseURL == "" {
		config.SandboxBaseURL = appleSandboxBaseURL
	}
	if config.Now == nil {
		config.Now = func() time.Time { return time.Now().UTC() }
	}
	return &AppleVerifier{
		issuerID: config.IssuerID, keyID: config.KeyID, privateKey: privateKey,
		bundleID: config.BundleID, appAppleID: config.AppAppleID,
		roots: roots, productIDs: products, httpClient: config.HTTPClient,
		allowSandbox:      config.AllowSandbox,
		productionBaseURL: strings.TrimRight(config.ProductionBaseURL, "/"),
		sandboxBaseURL:    strings.TrimRight(config.SandboxBaseURL, "/"), now: config.Now,
	}, nil
}

func parseApplePrivateKey(contents []byte) (*ecdsa.PrivateKey, error) {
	block, _ := pem.Decode(contents)
	if block == nil {
		return nil, fmt.Errorf("parse Apple IAP private key: PEM data is required")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	privateKey, ok := parsed.(*ecdsa.PrivateKey)
	if err != nil || !ok || privateKey.Curve != elliptic.P256() {
		return nil, fmt.Errorf("parse Apple IAP private key: ES256 PKCS8 key is required")
	}
	return privateKey, nil
}

func parseAppleRoots(contents []byte) (*x509.CertPool, error) {
	var certificates []*x509.Certificate
	remaining := contents
	for {
		block, rest := pem.Decode(remaining)
		if block == nil {
			break
		}
		remaining = rest
		parsed, err := x509.ParseCertificates(block.Bytes)
		if err != nil {
			return nil, fmt.Errorf("parse Apple root certificate: %w", err)
		}
		certificates = append(certificates, parsed...)
	}
	if len(certificates) == 0 {
		parsed, err := x509.ParseCertificates(contents)
		if err != nil {
			return nil, fmt.Errorf("parse Apple root certificate: %w", err)
		}
		certificates = parsed
	}
	pool := x509.NewCertPool()
	for _, certificate := range certificates {
		pool.AddCert(certificate)
	}
	return pool, nil
}
