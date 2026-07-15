package billing

import (
	"strings"
	"time"

	"github.com/google/uuid"
)

type appleTransactionClaims struct {
	TransactionID         string `json:"transactionId"`
	OriginalTransactionID string `json:"originalTransactionId"`
	BundleID              string `json:"bundleId"`
	ProductID             string `json:"productId"`
	ProductType           string `json:"type"`
	Environment           string `json:"environment"`
	Storefront            string `json:"storefront"`
	AppAccountToken       string `json:"appAccountToken"`
	PurchaseDate          int64  `json:"purchaseDate"`
	ExpiresDate           *int64 `json:"expiresDate"`
	RevocationDate        *int64 `json:"revocationDate"`
	SignedDate            int64  `json:"signedDate"`
}

func (verifier *AppleVerifier) validateClaims(
	claims appleTransactionClaims,
	transactionID string,
	environment Environment,
) (VerifiedTransaction, error) {
	return verifier.validateClaimsWithAccountToken(claims, transactionID, environment, true)
}

func (verifier *AppleVerifier) validateClaimsWithAccountToken(
	claims appleTransactionClaims,
	transactionID string,
	environment Environment,
	requireAccountToken bool,
) (VerifiedTransaction, error) {
	if claims.TransactionID != transactionID || claims.OriginalTransactionID == "" ||
		claims.BundleID != verifier.bundleID || claims.Storefront == "" ||
		claims.PurchaseDate <= 0 || claims.SignedDate <= 0 || !validAppleProductType(claims.ProductType) {
		return VerifiedTransaction{}, ErrVerificationFailed
	}
	if claims.ProductType == "Auto-Renewable Subscription" && claims.ExpiresDate == nil {
		return VerifiedTransaction{}, ErrVerificationFailed
	}
	wantEnvironment := "Production"
	if environment == EnvironmentSandbox {
		wantEnvironment = "Sandbox"
	}
	if claims.Environment != wantEnvironment {
		return VerifiedTransaction{}, ErrVerificationFailed
	}
	if _, allowed := verifier.productIDs[claims.ProductID]; !allowed {
		return VerifiedTransaction{}, ErrVerificationFailed
	}
	accountToken := ""
	if claims.AppAccountToken != "" {
		parsedAccountToken, err := uuid.Parse(claims.AppAccountToken)
		if err != nil {
			return VerifiedTransaction{}, ErrVerificationFailed
		}
		accountToken = parsedAccountToken.String()
	} else if requireAccountToken {
		return VerifiedTransaction{}, ErrVerificationFailed
	}
	transaction := VerifiedTransaction{
		Storefront: strings.ToUpper(claims.Storefront), TransactionID: claims.TransactionID,
		OriginalTransactionID: claims.OriginalTransactionID, ProductID: claims.ProductID,
		Environment: environment, PurchaseAt: time.UnixMilli(claims.PurchaseDate),
		AppAccountToken: accountToken, Status: StateActive,
	}
	if claims.ExpiresDate != nil {
		if *claims.ExpiresDate <= 0 {
			return VerifiedTransaction{}, ErrVerificationFailed
		}
		expiresAt := time.UnixMilli(*claims.ExpiresDate)
		transaction.ExpiresAt = &expiresAt
		if !expiresAt.After(verifier.now()) {
			transaction.Status = StateExpired
		}
	}
	if claims.RevocationDate != nil {
		if *claims.RevocationDate <= 0 {
			return VerifiedTransaction{}, ErrVerificationFailed
		}
		revokedAt := time.UnixMilli(*claims.RevocationDate)
		transaction.RevokedAt = &revokedAt
		transaction.Status = StateRevoked
	}
	return transaction, nil
}

func validAppleProductType(productType string) bool {
	switch productType {
	case "Auto-Renewable Subscription", "Non-Consumable":
		return true
	default:
		return false
	}
}
