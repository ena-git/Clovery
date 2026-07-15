package billing

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/asn1"
	"encoding/base64"
	"encoding/json"
	"math/big"
	"net/http"
	"testing"
	"time"
)

type appleCertificateFixture struct {
	rootDER  []byte
	leafKey  *ecdsa.PrivateKey
	x5cChain []string
}

func newAppleCertificateFixture(t *testing.T) appleCertificateFixture {
	t.Helper()
	now := time.Now().UTC()
	rootKey := newCertificateKey(t)
	rootTemplate := certificateTemplate(1, "Apple Test Root", now)
	rootTemplate.IsCA = true
	rootTemplate.KeyUsage = x509.KeyUsageCertSign | x509.KeyUsageCRLSign
	rootDER := createCertificate(t, rootTemplate, rootTemplate, &rootKey.PublicKey, rootKey)
	rootCertificate := parseCertificate(t, rootDER)

	intermediateKey := newCertificateKey(t)
	intermediateTemplate := certificateTemplate(2, "Apple Test Intermediate", now)
	intermediateTemplate.IsCA = true
	intermediateTemplate.KeyUsage = x509.KeyUsageCertSign | x509.KeyUsageCRLSign
	intermediateTemplate.ExtraExtensions = []pkix.Extension{appleOIDExtension(
		asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 2, 1},
	)}
	intermediateDER := createCertificate(
		t, intermediateTemplate, rootCertificate, &intermediateKey.PublicKey, rootKey,
	)
	intermediateCertificate := parseCertificate(t, intermediateDER)

	leafKey := newCertificateKey(t)
	leafTemplate := certificateTemplate(3, "Apple Test Signing", now)
	leafTemplate.KeyUsage = x509.KeyUsageDigitalSignature
	leafTemplate.ExtraExtensions = []pkix.Extension{appleOIDExtension(
		asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 11, 1},
	)}
	leafDER := createCertificate(
		t, leafTemplate, intermediateCertificate, &leafKey.PublicKey, intermediateKey,
	)
	return appleCertificateFixture{
		rootDER: rootDER,
		leafKey: leafKey,
		x5cChain: []string{
			base64.StdEncoding.EncodeToString(leafDER),
			base64.StdEncoding.EncodeToString(intermediateDER),
			base64.StdEncoding.EncodeToString(rootDER),
		},
	}
}

func (fixture appleCertificateFixture) signTransaction(t *testing.T, payload map[string]any) string {
	t.Helper()
	header := map[string]any{"alg": "ES256", "x5c": fixture.x5cChain}
	encodedHeader := encodeJWSPart(t, header)
	encodedPayload := encodeJWSPart(t, payload)
	signingInput := encodedHeader + "." + encodedPayload
	digest := sha256.Sum256([]byte(signingInput))
	r, s, err := ecdsa.Sign(rand.Reader, fixture.leafKey, digest[:])
	if err != nil {
		t.Fatalf("sign transaction: %v", err)
	}
	signature := make([]byte, 64)
	r.FillBytes(signature[:32])
	s.FillBytes(signature[32:])
	return signingInput + "." + base64.RawURLEncoding.EncodeToString(signature)
}

func appleTransactionPayload(now time.Time) map[string]any {
	return map[string]any{
		"transactionId": "tx-1", "originalTransactionId": "original-1",
		"bundleId": "com.clovery.app", "productId": "com.clovery.pro.monthly",
		"type": "Auto-Renewable Subscription", "environment": "Sandbox", "storefront": "USA",
		"appAccountToken": billingAccountID, "purchaseDate": now.Add(-time.Hour).UnixMilli(),
		"expiresDate": now.Add(time.Hour).UnixMilli(), "signedDate": now.UnixMilli(),
	}
}

func signedTransactionDoer(t *testing.T, signed string) HTTPDoer {
	t.Helper()
	return appleHTTPDoer(func(_ *http.Request) (*http.Response, error) {
		contents, _ := json.Marshal(map[string]string{"signedTransactionInfo": signed})
		return appleHTTPResponse(http.StatusOK, contents), nil
	})
}

func certificateTemplate(serial int64, commonName string, now time.Time) *x509.Certificate {
	return &x509.Certificate{
		SerialNumber: big.NewInt(serial), Subject: pkix.Name{CommonName: commonName},
		NotBefore: now.Add(-24 * time.Hour), NotAfter: now.Add(24 * time.Hour),
		BasicConstraintsValid: true,
	}
}

func appleOIDExtension(identifier asn1.ObjectIdentifier) pkix.Extension {
	return pkix.Extension{Id: identifier, Value: []byte{0x05, 0x00}}
}

func newCertificateKey(t *testing.T) *ecdsa.PrivateKey {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("generate certificate key: %v", err)
	}
	return key
}

func createCertificate(
	t *testing.T,
	template *x509.Certificate,
	parent *x509.Certificate,
	publicKey *ecdsa.PublicKey,
	signer *ecdsa.PrivateKey,
) []byte {
	t.Helper()
	der, err := x509.CreateCertificate(rand.Reader, template, parent, publicKey, signer)
	if err != nil {
		t.Fatalf("create certificate: %v", err)
	}
	return der
}

func parseCertificate(t *testing.T, der []byte) *x509.Certificate {
	t.Helper()
	certificate, err := x509.ParseCertificate(der)
	if err != nil {
		t.Fatalf("parse certificate: %v", err)
	}
	return certificate
}

func encodeJWSPart(t *testing.T, value any) string {
	t.Helper()
	encoded, err := json.Marshal(value)
	if err != nil {
		t.Fatalf("encode JWS part: %v", err)
	}
	return base64.RawURLEncoding.EncodeToString(encoded)
}
