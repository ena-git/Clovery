package billing

import (
	"encoding/json"
	"strings"
	"time"

	"github.com/google/uuid"
)

type appleRenewalClaims struct {
	OriginalTransactionID  string `json:"originalTransactionId"`
	ProductID              string `json:"productId"`
	Environment            string `json:"environment"`
	AppAccountToken        string `json:"appAccountToken"`
	GracePeriodExpiresDate *int64 `json:"gracePeriodExpiresDate"`
	RenewalDate            int64  `json:"renewalDate"`
	SignedDate             int64  `json:"signedDate"`
}

func (verifier *AppleVerifier) applyRenewalStatus(
	transaction *VerifiedTransaction,
	status int,
	signedRenewalInfo string,
) error {
	if status < 1 || status > 5 || strings.TrimSpace(signedRenewalInfo) == "" {
		return ErrVerificationFailed
	}
	verified, err := verifier.verifyAppleJWS(signedRenewalInfo)
	if err != nil {
		return err
	}
	var claims appleRenewalClaims
	if json.Unmarshal(verified.Payload, &claims) != nil || claims.SignedDate <= 0 ||
		claims.RenewalDate <= 0 || claims.OriginalTransactionID != transaction.OriginalTransactionID ||
		claims.ProductID != transaction.ProductID {
		return ErrVerificationFailed
	}
	wantEnvironment := "Production"
	if transaction.Environment == EnvironmentSandbox {
		wantEnvironment = "Sandbox"
	}
	if claims.Environment != wantEnvironment {
		return ErrVerificationFailed
	}
	if claims.AppAccountToken != "" {
		accountToken, parseErr := uuid.Parse(claims.AppAccountToken)
		if parseErr != nil || accountToken.String() != transaction.AppAccountToken {
			return ErrVerificationFailed
		}
	}

	renewalDate := time.UnixMilli(claims.RenewalDate)
	switch status {
	case 1:
		transaction.Status = StateActive
		if transaction.ExpiresAt == nil || renewalDate.After(*transaction.ExpiresAt) {
			transaction.ExpiresAt = &renewalDate
		}
	case 2, 3:
		transaction.Status = StateExpired
	case 4:
		if claims.GracePeriodExpiresDate == nil || *claims.GracePeriodExpiresDate <= 0 {
			return ErrVerificationFailed
		}
		graceExpiresAt := time.UnixMilli(*claims.GracePeriodExpiresDate)
		if graceExpiresAt.Before(renewalDate) {
			return ErrVerificationFailed
		}
		transaction.Status = StateActive
		transaction.ExpiresAt = &graceExpiresAt
	case 5:
		transaction.Status = StateRevoked
	}
	return nil
}
