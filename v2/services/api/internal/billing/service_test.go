package billing

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"
)

const (
	billingAccountID = "11111111-1111-4111-8111-111111111111"
	otherAccountID   = "22222222-2222-4222-8222-222222222222"
)

func TestServiceGrantsOnlyMatchingVerifiedAccount(t *testing.T) {
	transaction := verifiedTransactionFixture()
	verifier := &stubVerifier{transactions: map[string]VerifiedTransaction{"tx-1": transaction}}
	repository := &stubRepository{}
	service, err := NewService(verifier, repository)
	if err != nil {
		t.Fatalf("NewService() error = %v", err)
	}

	entitlement, err := service.Verify(
		context.Background(), billingAccountID, "tx-1", EnvironmentSandbox,
	)
	if err != nil {
		t.Fatalf("Verify() error = %v", err)
	}
	if repository.recordedAccountID != billingAccountID || repository.recorded.ProductID != transaction.ProductID {
		t.Fatalf("recorded account = %q, transaction = %#v", repository.recordedAccountID, repository.recorded)
	}
	if entitlement.ProductID != transaction.ProductID || entitlement.State != StateActive {
		t.Fatalf("entitlement = %#v", entitlement)
	}
}

func TestServiceRejectsVerifiedTransactionForAnotherAccount(t *testing.T) {
	transaction := verifiedTransactionFixture()
	transaction.AppAccountToken = otherAccountID
	repository := &stubRepository{}
	service, _ := NewService(
		&stubVerifier{transactions: map[string]VerifiedTransaction{"tx-1": transaction}},
		repository,
	)

	_, err := service.Verify(context.Background(), billingAccountID, "tx-1", EnvironmentSandbox)
	if !errors.Is(err, ErrAccountMismatch) {
		t.Fatalf("Verify() error = %v, want ErrAccountMismatch", err)
	}
	if repository.recordCalls != 0 {
		t.Fatalf("repository Record() calls = %d", repository.recordCalls)
	}
}

func TestServiceDoesNotPromoteInactiveTransactions(t *testing.T) {
	for _, state := range []State{StateRevoked, StateCancelled, StateFailed} {
		t.Run(string(state), func(t *testing.T) {
			transaction := verifiedTransactionFixture()
			transaction.Status = state
			repository := &stubRepository{}
			service, _ := NewService(
				&stubVerifier{transactions: map[string]VerifiedTransaction{"tx-1": transaction}},
				repository,
			)

			entitlement, err := service.Verify(
				context.Background(), billingAccountID, "tx-1", EnvironmentSandbox,
			)
			if err != nil {
				t.Fatalf("Verify() error = %v", err)
			}
			if repository.recorded.Status != state || entitlement.State != state {
				t.Fatalf("recorded status = %q, entitlement = %#v", repository.recorded.Status, entitlement)
			}
		})
	}
}

func TestServiceRestoreReturnsAuthenticatedAccountEntitlements(t *testing.T) {
	first := verifiedTransactionFixture()
	second := verifiedTransactionFixture()
	second.TransactionID = "tx-2"
	second.ProductID = "com.clovery.pro.yearly"
	want := []Entitlement{{ProductID: first.ProductID}, {ProductID: second.ProductID}}
	repository := &stubRepository{listed: want}
	service, _ := NewService(
		&stubVerifier{transactions: map[string]VerifiedTransaction{"tx-1": first, "tx-2": second}},
		repository,
	)

	got, err := service.Restore(
		context.Background(), billingAccountID, []string{"tx-1", "tx-2"}, EnvironmentSandbox,
	)
	if err != nil {
		t.Fatalf("Restore() error = %v", err)
	}
	if repository.recordCalls != 2 || repository.listedAccountID != billingAccountID {
		t.Fatalf("record calls = %d, list account = %q", repository.recordCalls, repository.listedAccountID)
	}
	if len(got) != len(want) || got[1].ProductID != want[1].ProductID {
		t.Fatalf("Restore() = %#v", got)
	}
}

func TestServiceListExpiresStoredEntitlementAtReadTime(t *testing.T) {
	expiresAt := time.Date(2026, 7, 14, 12, 0, 0, 0, time.UTC)
	repository := &stubRepository{listed: []Entitlement{{
		ProductID: "com.clovery.pro.monthly", State: StateActive, ExpiresAt: &expiresAt,
	}}}
	service, _ := NewService(&stubVerifier{}, repository)
	service.now = func() time.Time { return expiresAt.Add(time.Second) }

	entitlements, err := service.List(context.Background(), billingAccountID)
	if err != nil {
		t.Fatalf("List() error = %v", err)
	}
	if len(entitlements) != 1 || entitlements[0].State != StateExpired {
		t.Fatalf("List() = %#v", entitlements)
	}
}

func TestServiceListReturnsEmptyArrayInsteadOfNull(t *testing.T) {
	service, _ := NewService(&stubVerifier{}, &stubRepository{})
	entitlements, err := service.List(context.Background(), billingAccountID)
	if err != nil {
		t.Fatalf("List() error = %v", err)
	}
	if entitlements == nil || len(entitlements) != 0 {
		t.Fatalf("List() = %#v", entitlements)
	}
}

func TestServiceProcessesNotificationForTransactionAccount(t *testing.T) {
	transaction := verifiedTransactionFixture()
	revokedAt := transaction.PurchaseAt.Add(time.Minute)
	transaction.RevokedAt = &revokedAt
	notification := AppleNotification{
		ID: "33333333-3333-4333-8333-333333333333", Type: "REFUND",
		Environment: transaction.Environment, SignedAt: revokedAt,
		PayloadSHA256: strings.Repeat("a", 64), Transaction: &transaction,
	}
	verifier := &stubVerifier{notification: notification}
	repository := &stubRepository{}
	service, err := NewService(verifier, repository)
	if err != nil {
		t.Fatalf("NewService() error = %v", err)
	}

	if err := service.ProcessAppleNotification(context.Background(), "signed-payload"); err != nil {
		t.Fatalf("ProcessAppleNotification() error = %v", err)
	}
	if repository.notificationAccountID != billingAccountID ||
		repository.notification.Transaction.Status != StateRevoked {
		t.Fatalf("notification account = %q, notification = %#v", repository.notificationAccountID, repository.notification)
	}
}

func TestServiceAcknowledgesVerifiedNotificationWithoutTransaction(t *testing.T) {
	repository := &stubRepository{}
	now := time.Date(2026, time.July, 14, 19, 0, 0, 0, time.UTC)
	service, _ := NewService(
		&stubVerifier{notification: AppleNotification{
			ID: "33333333-3333-4333-8333-333333333333", Type: "TEST",
			SignedAt: now, PayloadSHA256: strings.Repeat("a", 64),
		}},
		repository,
	)

	if err := service.ProcessAppleNotification(context.Background(), "signed-payload"); err != nil {
		t.Fatalf("ProcessAppleNotification() error = %v", err)
	}
	if repository.notificationCalls != 1 || repository.notificationAccountID != "" {
		t.Fatalf("RecordNotification() calls = %d", repository.notificationCalls)
	}
}

func TestServicePersistsLegacyNotificationWithoutAccountMapping(t *testing.T) {
	repository := &stubRepository{}
	now := time.Date(2026, time.July, 14, 19, 0, 0, 0, time.UTC)
	transaction := verifiedTransactionFixture()
	transaction.AppAccountToken = ""
	service, _ := NewService(
		&stubVerifier{notification: AppleNotification{
			ID: "33333333-3333-4333-8333-333333333333", Type: "DID_RENEW",
			Environment: transaction.Environment, SignedAt: now,
			PayloadSHA256: strings.Repeat("a", 64), Transaction: &transaction,
		}},
		repository,
	)

	if err := service.ProcessAppleNotification(context.Background(), "signed-payload"); err != nil {
		t.Fatalf("ProcessAppleNotification() legacy error = %v", err)
	}
	if repository.notificationCalls != 1 || repository.notificationAccountID != "" ||
		repository.notification.Transaction == nil {
		t.Fatalf("legacy notification repository state = %#v", repository)
	}
}

type stubVerifier struct {
	transactions map[string]VerifiedTransaction
	notification AppleNotification
	legacyProof  VerifiedTransaction
	assigned     VerifiedTransaction
	assignCalls  int
	err          error
}

func (stub *stubVerifier) Verify(
	_ context.Context,
	transactionID string,
	_ Environment,
) (VerifiedTransaction, error) {
	if stub.err != nil {
		return VerifiedTransaction{}, stub.err
	}
	return stub.transactions[transactionID], nil
}

func (stub *stubVerifier) VerifyNotification(context.Context, string) (AppleNotification, error) {
	if stub.err != nil {
		return AppleNotification{}, stub.err
	}
	return stub.notification, nil
}

func (stub *stubVerifier) VerifyLegacyProof(
	context.Context,
	string,
	Environment,
) (VerifiedTransaction, error) {
	if stub.err != nil {
		return VerifiedTransaction{}, stub.err
	}
	return stub.legacyProof, nil
}

func (stub *stubVerifier) AssignAccountToken(
	context.Context,
	string,
	string,
	string,
	Environment,
) (VerifiedTransaction, error) {
	stub.assignCalls++
	if stub.err != nil {
		return VerifiedTransaction{}, stub.err
	}
	return stub.assigned, nil
}

type stubRepository struct {
	recordedAccountID     string
	recorded              VerifiedTransaction
	recordCalls           int
	listedAccountID       string
	listed                []Entitlement
	notificationAccountID string
	notification          AppleNotification
	notificationCalls     int
	reserveCalls          int
}

func (stub *stubRepository) ReservePurchaseChain(
	_ context.Context,
	_ string,
	_ VerifiedTransaction,
	_ time.Time,
) error {
	stub.reserveCalls++
	return nil
}

func (stub *stubRepository) RecordNotification(
	_ context.Context,
	accountID string,
	notification AppleNotification,
	_ time.Time,
) error {
	stub.notificationCalls++
	stub.notificationAccountID = accountID
	stub.notification = notification
	return nil
}

func (stub *stubRepository) Record(
	_ context.Context,
	accountID string,
	transaction VerifiedTransaction,
	_ time.Time,
) (Entitlement, error) {
	stub.recordCalls++
	stub.recordedAccountID = accountID
	stub.recorded = transaction
	return Entitlement{ProductID: transaction.ProductID, State: transaction.Status}, nil
}

func (stub *stubRepository) List(_ context.Context, accountID string) ([]Entitlement, error) {
	stub.listedAccountID = accountID
	return stub.listed, nil
}

func verifiedTransactionFixture() VerifiedTransaction {
	now := time.Date(2026, 7, 14, 12, 0, 0, 0, time.UTC)
	expiresAt := now.Add(30 * 24 * time.Hour)
	return VerifiedTransaction{
		Storefront: "USA", TransactionID: "tx-1", OriginalTransactionID: "original-1",
		ProductID: "com.clovery.pro.monthly", Environment: EnvironmentSandbox,
		PurchaseAt: now, ExpiresAt: &expiresAt, AppAccountToken: billingAccountID,
		Status: StateActive, Metadata: VerificationMetadata{
			Source: "test", SignedAt: now, JWSHash: strings.Repeat("a", 64),
		},
	}
}
