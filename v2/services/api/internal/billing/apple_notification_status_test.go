package billing

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestAppleVerifierKeepsSubscriptionActiveDuringBillingGracePeriod(t *testing.T) {
	fixture := newAppleCertificateFixture(t)
	_, privateKeyPEM := newAPISigningKey(t)
	now := time.Date(2026, time.July, 14, 20, 0, 0, 0, time.UTC)
	graceExpiresAt := now.Add(24 * time.Hour)
	signedNotification := signedSubscriptionNotification(
		t, fixture, now, 4, graceExpiresAt.UnixMilli(), "original-1",
	)
	verifier := newTestAppleVerifier(t, fixture.rootDER, privateKeyPEM, appleHTTPDoer(nil), now)

	notification, err := verifier.VerifyNotification(context.Background(), signedNotification)
	if err != nil {
		t.Fatalf("VerifyNotification() grace period error = %v", err)
	}
	if notification.Transaction == nil || notification.Transaction.Status != StateActive ||
		notification.Transaction.ExpiresAt == nil ||
		!notification.Transaction.ExpiresAt.Equal(graceExpiresAt) {
		t.Fatalf("VerifyNotification() grace transaction = %#v", notification.Transaction)
	}
}

func TestAppleVerifierMapsSubscriptionNotificationStatuses(t *testing.T) {
	for _, testCase := range []struct {
		name   string
		status int
		want   State
	}{
		{name: "expired", status: 2, want: StateExpired},
		{name: "billing retry", status: 3, want: StateExpired},
		{name: "revoked", status: 5, want: StateRevoked},
	} {
		t.Run(testCase.name, func(t *testing.T) {
			fixture := newAppleCertificateFixture(t)
			_, privateKeyPEM := newAPISigningKey(t)
			now := time.Date(2026, time.July, 14, 20, 0, 0, 0, time.UTC)
			signedNotification := signedSubscriptionNotification(
				t, fixture, now, testCase.status, 0, "original-1",
			)
			verifier := newTestAppleVerifier(
				t, fixture.rootDER, privateKeyPEM, appleHTTPDoer(nil), now,
			)

			notification, err := verifier.VerifyNotification(context.Background(), signedNotification)
			if err != nil {
				t.Fatalf("VerifyNotification() status error = %v", err)
			}
			if notification.Transaction == nil || notification.Transaction.Status != testCase.want {
				t.Fatalf("VerifyNotification() transaction = %#v", notification.Transaction)
			}
		})
	}
}

func TestAppleVerifierRejectsGraceStatusWithoutValidRenewalInfo(t *testing.T) {
	fixture := newAppleCertificateFixture(t)
	_, privateKeyPEM := newAPISigningKey(t)
	now := time.Date(2026, time.July, 14, 20, 0, 0, 0, time.UTC)
	signedNotification := signedSubscriptionNotification(
		t, fixture, now, 4, now.Add(time.Hour).UnixMilli(), "another-original",
	)
	verifier := newTestAppleVerifier(t, fixture.rootDER, privateKeyPEM, appleHTTPDoer(nil), now)

	_, err := verifier.VerifyNotification(context.Background(), signedNotification)
	if !errors.Is(err, ErrVerificationFailed) {
		t.Fatalf("VerifyNotification() mismatched renewal error = %v", err)
	}
}

func signedSubscriptionNotification(
	t *testing.T,
	fixture appleCertificateFixture,
	now time.Time,
	status int,
	gracePeriodExpiresDate int64,
	originalTransactionID string,
) string {
	t.Helper()
	transactionPayload := appleTransactionPayload(now)
	expiredAt := now.Add(-time.Minute).UnixMilli()
	transactionPayload["expiresDate"] = expiredAt
	signedTransaction := fixture.signTransaction(t, transactionPayload)
	renewalPayload := map[string]any{
		"originalTransactionId": originalTransactionID,
		"productId":             "com.clovery.pro.monthly",
		"environment":           "Sandbox",
		"appAccountToken":       billingAccountID,
		"renewalDate":           expiredAt,
		"signedDate":            now.UnixMilli(),
	}
	if gracePeriodExpiresDate > 0 {
		renewalPayload["gracePeriodExpiresDate"] = gracePeriodExpiresDate
	}
	return fixture.signTransaction(t, map[string]any{
		"notificationType": "DID_FAIL_TO_RENEW",
		"subtype":          "GRACE_PERIOD",
		"notificationUUID": "33333333-3333-4333-8333-333333333333",
		"version":          "2.0",
		"signedDate":       now.UnixMilli(),
		"data": map[string]any{
			"bundleId": "com.clovery.app", "environment": "Sandbox", "status": status,
			"signedTransactionInfo": signedTransaction,
			"signedRenewalInfo":     fixture.signTransaction(t, renewalPayload),
		},
	})
}
