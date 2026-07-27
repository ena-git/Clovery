package billing

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestServiceReservesAndAssignsLegacyPurchaseToCloveryAccountID(t *testing.T) {
	proof := verifiedTransactionFixture()
	proof.AppAccountToken = ""
	assigned := proof
	assigned.AppAccountToken = billingAccountID
	verifier := &stubVerifier{legacyProof: proof, assigned: assigned}
	repository := &stubRepository{}
	service, _ := NewService(verifier, repository)

	entitlement, err := service.ClaimLegacy(
		context.Background(), billingAccountID, "signed-legacy-transaction", EnvironmentSandbox,
	)
	if err != nil {
		t.Fatalf("ClaimLegacy() error = %v", err)
	}
	if repository.reserveCalls != 1 || verifier.assignCalls != 1 || repository.recordCalls != 1 ||
		verifier.assignedAccountID != billingAccountID {
		t.Fatalf(
			"claim calls: reserve=%d assign=%d record=%d",
			repository.reserveCalls, verifier.assignCalls, repository.recordCalls,
		)
	}
	if entitlement.ProductID != assigned.ProductID || repository.recordedAccountID != billingAccountID {
		t.Fatalf("ClaimLegacy() entitlement = %#v, account = %q", entitlement, repository.recordedAccountID)
	}
}

func TestServiceReplaysLegacyTransactionAlreadyAssignedToSameAccount(t *testing.T) {
	proof := verifiedTransactionFixture()
	verifier := &stubVerifier{
		legacyProof:  proof,
		transactions: map[string]VerifiedTransaction{proof.TransactionID: proof},
	}
	repository := &stubRepository{}
	service, _ := NewService(verifier, repository)

	_, err := service.ClaimLegacy(
		context.Background(), billingAccountID, "signed-legacy-transaction", EnvironmentSandbox,
	)
	if err != nil || repository.reserveCalls != 0 || verifier.assignCalls != 0 || repository.recordCalls != 1 {
		t.Fatalf(
			"ClaimLegacy(replay) reserve=%d assign=%d record=%d error=%v",
			repository.reserveCalls, verifier.assignCalls, repository.recordCalls, err,
		)
	}
}

func TestServiceFailedAppleAssignmentDoesNotCreateEntitlement(t *testing.T) {
	proof := verifiedTransactionFixture()
	proof.AppAccountToken = ""
	verifier := &stubVerifier{legacyProof: proof, assignErr: ErrVerificationUnavailable}
	repository := &stubRepository{}
	service, _ := NewService(verifier, repository)

	_, err := service.ClaimLegacy(
		context.Background(), billingAccountID, "signed-legacy-transaction", EnvironmentSandbox,
	)
	if !errors.Is(err, ErrVerificationUnavailable) || repository.recordCalls != 0 {
		t.Fatalf("ClaimLegacy() record calls = %d, error = %v", repository.recordCalls, err)
	}
}

func TestServiceRejectsExpiredLegacySubscriptionProof(t *testing.T) {
	proof := verifiedTransactionFixture()
	proof.AppAccountToken = ""
	expiredAt := time.Now().UTC().Add(-time.Hour)
	proof.ExpiresAt = &expiredAt
	proof.Status = StateExpired
	verifier := &stubVerifier{legacyProof: proof}
	repository := &stubRepository{}
	service, _ := NewService(verifier, repository)

	_, err := service.ClaimLegacy(
		context.Background(), billingAccountID, "signed-expired-transaction", EnvironmentSandbox,
	)
	if !errors.Is(err, ErrVerificationFailed) {
		t.Fatalf("ClaimLegacy() expired proof error = %v", err)
	}
	if repository.reserveCalls != 0 || verifier.assignCalls != 0 {
		t.Fatal("ClaimLegacy() reserved an expired purchase")
	}
}

func TestServiceRejectsLegacyTransactionOwnedByAnotherAccount(t *testing.T) {
	proof := verifiedTransactionFixture()
	proof.AppAccountToken = otherAccountID
	verifier := &stubVerifier{legacyProof: proof}
	repository := &stubRepository{}
	service, _ := NewService(verifier, repository)

	_, err := service.ClaimLegacy(
		context.Background(), billingAccountID, "signed-legacy-transaction", EnvironmentSandbox,
	)
	if !errors.Is(err, ErrTransactionClaimed) {
		t.Fatalf("ClaimLegacy() error = %v, want ErrTransactionClaimed", err)
	}
	if repository.reserveCalls != 0 || verifier.assignCalls != 0 || repository.recordCalls != 0 {
		t.Fatalf("ClaimLegacy() mutated state for another account")
	}
}
