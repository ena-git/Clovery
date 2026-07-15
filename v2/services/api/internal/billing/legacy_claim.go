package billing

import (
	"context"
	"strings"
	"time"

	"github.com/google/uuid"
)

func (service *Service) ClaimLegacy(
	ctx context.Context,
	accountID string,
	signedTransactionInfo string,
	environment Environment,
) (Entitlement, error) {
	accountUUID, err := uuid.Parse(accountID)
	signedTransactionInfo = strings.TrimSpace(signedTransactionInfo)
	if err != nil || !environment.Valid() || signedTransactionInfo == "" ||
		len(signedTransactionInfo) > maximumAppleNotificationSize {
		return Entitlement{}, ErrInvalidRequest
	}
	proof, err := service.verifier.VerifyLegacyProof(ctx, signedTransactionInfo, environment)
	if err != nil {
		return Entitlement{}, err
	}
	if !validLegacyProof(proof, environment, service.now()) {
		return Entitlement{}, ErrVerificationFailed
	}
	if proof.AppAccountToken != "" {
		proofAccountID, parseErr := uuid.Parse(proof.AppAccountToken)
		if parseErr != nil {
			return Entitlement{}, ErrVerificationFailed
		}
		if proofAccountID != accountUUID {
			return Entitlement{}, ErrTransactionClaimed
		}
		return service.recordCurrentLegacyTransaction(ctx, accountUUID.String(), proof, environment)
	}
	if err := service.repository.ReservePurchaseChain(
		ctx, accountUUID.String(), proof, service.now(),
	); err != nil {
		return Entitlement{}, err
	}
	assigned, err := service.verifier.AssignAccountToken(
		ctx, proof.OriginalTransactionID, proof.TransactionID, accountUUID.String(), environment,
	)
	if err != nil {
		return Entitlement{}, err
	}
	if !sameLegacyTransaction(proof, assigned) || assigned.AppAccountToken != accountUUID.String() {
		return Entitlement{}, ErrVerificationFailed
	}
	assigned.Status = assigned.stateAt(service.now())
	return service.repository.Record(ctx, accountUUID.String(), assigned, service.now())
}

func (service *Service) recordCurrentLegacyTransaction(
	ctx context.Context,
	accountID string,
	proof VerifiedTransaction,
	environment Environment,
) (Entitlement, error) {
	current, err := service.verifier.Verify(ctx, proof.TransactionID, environment)
	if err != nil {
		return Entitlement{}, err
	}
	if !sameLegacyTransaction(proof, current) || current.AppAccountToken != accountID {
		return Entitlement{}, ErrVerificationFailed
	}
	current.Status = current.stateAt(service.now())
	return service.repository.Record(ctx, accountID, current, service.now())
}

func validLegacyProof(
	transaction VerifiedTransaction,
	environment Environment,
	now time.Time,
) bool {
	if transaction.Status != StateActive ||
		(transaction.ExpiresAt != nil && !transaction.ExpiresAt.After(now)) {
		return false
	}
	return transaction.Environment == environment && transaction.Storefront != "" &&
		transaction.TransactionID != "" && len(transaction.TransactionID) <= 128 &&
		transaction.OriginalTransactionID != "" && len(transaction.OriginalTransactionID) <= 128 &&
		transaction.ProductID != "" && transaction.Status.Valid() && !transaction.PurchaseAt.IsZero()
}

func sameLegacyTransaction(proof VerifiedTransaction, verified VerifiedTransaction) bool {
	return verified.TransactionID == proof.TransactionID &&
		verified.OriginalTransactionID == proof.OriginalTransactionID &&
		verified.ProductID == proof.ProductID && verified.Storefront == proof.Storefront &&
		verified.Environment == proof.Environment && verified.Status.Valid()
}
