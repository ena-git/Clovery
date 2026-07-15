package billing

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"crypto/x509"
	"encoding/asn1"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"math/big"
	"time"
)

var (
	appleLeafOID         = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 11, 1}
	appleIntermediateOID = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 2, 1}
)

type appleJWSHeader struct {
	Algorithm string   `json:"alg"`
	X5C       []string `json:"x5c"`
}

type verifiedAppleJWS struct {
	Payload           []byte
	Hash              string
	CertificateSerial string
}

func (verifier *AppleVerifier) verifySignedTransaction(
	signed string,
	transactionID string,
	environment Environment,
) (VerifiedTransaction, error) {
	verified, err := verifier.verifyAppleJWS(signed)
	if err != nil {
		return VerifiedTransaction{}, err
	}
	return verifier.transactionFromVerifiedJWS(verified, transactionID, environment, "app_store_server_api")
}

func (verifier *AppleVerifier) transactionFromVerifiedJWS(
	verified verifiedAppleJWS,
	transactionID string,
	environment Environment,
	source string,
) (VerifiedTransaction, error) {
	return verifier.transactionFromVerifiedJWSWithAccountToken(
		verified, transactionID, environment, source, true,
	)
}

func (verifier *AppleVerifier) transactionFromVerifiedJWSWithAccountToken(
	verified verifiedAppleJWS,
	transactionID string,
	environment Environment,
	source string,
	requireAccountToken bool,
) (VerifiedTransaction, error) {
	var claims appleTransactionClaims
	if json.Unmarshal(verified.Payload, &claims) != nil {
		return VerifiedTransaction{}, ErrVerificationFailed
	}
	transaction, err := verifier.validateClaimsWithAccountToken(
		claims, transactionID, environment, requireAccountToken,
	)
	if err != nil {
		return VerifiedTransaction{}, err
	}
	transaction.Metadata = VerificationMetadata{
		Source: source, SignedAt: time.UnixMilli(claims.SignedDate),
		JWSHash: verified.Hash, CertificateSerial: verified.CertificateSerial,
	}
	return transaction, nil
}

func (verifier *AppleVerifier) verifyAppleJWS(signed string) (verifiedAppleJWS, error) {
	parts := splitCompactJWS(signed)
	if len(parts) != 3 {
		return verifiedAppleJWS{}, ErrVerificationFailed
	}
	var header appleJWSHeader
	if decodeJWSJSON(parts[0], &header) != nil || header.Algorithm != "ES256" || len(header.X5C) != 3 {
		return verifiedAppleJWS{}, ErrVerificationFailed
	}
	payload, err := base64.RawURLEncoding.Strict().DecodeString(parts[1])
	if err != nil {
		return verifiedAppleJWS{}, ErrVerificationFailed
	}
	var timing struct {
		SignedDate int64 `json:"signedDate"`
	}
	if json.Unmarshal(payload, &timing) != nil {
		return verifiedAppleJWS{}, ErrVerificationFailed
	}
	certificates, err := parseJWSCertificates(header.X5C)
	if err != nil || !hasCertificateOID(certificates[0], appleLeafOID) ||
		!hasCertificateOID(certificates[1], appleIntermediateOID) {
		return verifiedAppleJWS{}, ErrVerificationFailed
	}
	effectiveTime := verifier.now().UTC()
	if timing.SignedDate > 0 {
		effectiveTime = time.UnixMilli(timing.SignedDate)
	}
	intermediates := x509.NewCertPool()
	intermediates.AddCert(certificates[1])
	if _, err := certificates[0].Verify(x509.VerifyOptions{
		Roots: verifier.roots, Intermediates: intermediates, CurrentTime: effectiveTime,
		KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageAny},
	}); err != nil {
		return verifiedAppleJWS{}, ErrVerificationFailed
	}
	publicKey, ok := certificates[0].PublicKey.(*ecdsa.PublicKey)
	signature, err := base64.RawURLEncoding.Strict().DecodeString(parts[2])
	if err != nil || !ok || publicKey.Curve != elliptic.P256() || len(signature) != 64 {
		return verifiedAppleJWS{}, ErrVerificationFailed
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	if !ecdsa.Verify(
		publicKey, digest[:], new(big.Int).SetBytes(signature[:32]), new(big.Int).SetBytes(signature[32:]),
	) {
		return verifiedAppleJWS{}, ErrVerificationFailed
	}
	jwsHash := sha256.Sum256([]byte(signed))
	return verifiedAppleJWS{
		Payload: payload, Hash: hex.EncodeToString(jwsHash[:]),
		CertificateSerial: certificates[0].SerialNumber.String(),
	}, nil
}

func splitCompactJWS(value string) []string {
	var parts []string
	start := 0
	for index := 0; index < len(value); index++ {
		if value[index] == '.' {
			parts = append(parts, value[start:index])
			start = index + 1
		}
	}
	return append(parts, value[start:])
}

func decodeJWSJSON(encoded string, destination any) error {
	contents, err := base64.RawURLEncoding.Strict().DecodeString(encoded)
	if err != nil {
		return err
	}
	return json.Unmarshal(contents, destination)
}

func parseJWSCertificates(encoded []string) ([]*x509.Certificate, error) {
	certificates := make([]*x509.Certificate, 0, len(encoded))
	for _, value := range encoded {
		der, err := base64.StdEncoding.Strict().DecodeString(value)
		if err != nil {
			return nil, err
		}
		certificate, err := x509.ParseCertificate(der)
		if err != nil {
			return nil, err
		}
		certificates = append(certificates, certificate)
	}
	return certificates, nil
}

func hasCertificateOID(certificate *x509.Certificate, identifier asn1.ObjectIdentifier) bool {
	for _, extension := range certificate.Extensions {
		if extension.Id.Equal(identifier) {
			return true
		}
	}
	return false
}
