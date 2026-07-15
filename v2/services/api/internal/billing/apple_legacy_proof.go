package billing

import (
	"context"
	"encoding/json"
	"strings"
	"time"
)

func (verifier *AppleVerifier) VerifyLegacyProof(
	_ context.Context,
	signedTransactionInfo string,
	environment Environment,
) (VerifiedTransaction, error) {
	if !environment.Valid() || (environment == EnvironmentSandbox && !verifier.allowSandbox) {
		return VerifiedTransaction{}, ErrVerificationFailed
	}
	verified, err := verifier.verifyAppleJWS(strings.TrimSpace(signedTransactionInfo))
	if err != nil {
		return VerifiedTransaction{}, err
	}
	var claims appleTransactionClaims
	if json.Unmarshal(verified.Payload, &claims) != nil {
		return VerifiedTransaction{}, ErrVerificationFailed
	}
	transaction, err := verifier.validateClaimsWithAccountToken(
		claims, claims.TransactionID, environment, false,
	)
	if err != nil {
		return VerifiedTransaction{}, err
	}
	transaction.Metadata = VerificationMetadata{
		Source: "storekit_signed_transaction_legacy_claim", SignedAt: time.UnixMilli(claims.SignedDate),
		JWSHash: verified.Hash, CertificateSerial: verified.CertificateSerial,
	}
	return transaction, nil
}
