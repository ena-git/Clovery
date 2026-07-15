package billing

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestAppleVerifierVerifiesServerNotificationAndNestedTransaction(t *testing.T) {
	fixture := newAppleCertificateFixture(t)
	_, privateKeyPEM := newAPISigningKey(t)
	now := time.Date(2026, time.July, 14, 19, 0, 0, 0, time.UTC)
	transactionPayload := appleTransactionPayload(now)
	revokedAt := now.Add(-time.Minute).UnixMilli()
	transactionPayload["revocationDate"] = revokedAt
	signedTransaction := fixture.signTransaction(t, transactionPayload)
	signedNotification := fixture.signTransaction(t, map[string]any{
		"notificationType": "REFUND",
		"notificationUUID": "33333333-3333-4333-8333-333333333333",
		"version":          "2.0",
		"signedDate":       now.UnixMilli(),
		"data": map[string]any{
			"bundleId": "com.clovery.app", "environment": "Sandbox",
			"signedTransactionInfo": signedTransaction,
		},
	})
	verifier := newTestAppleVerifier(t, fixture.rootDER, privateKeyPEM, appleHTTPDoer(nil), now)

	notification, err := verifier.VerifyNotification(context.Background(), signedNotification)
	if err != nil {
		t.Fatalf("VerifyNotification() error = %v", err)
	}
	if notification.ID != "33333333-3333-4333-8333-333333333333" ||
		notification.Type != "REFUND" || notification.Transaction == nil ||
		notification.Transaction.Status != StateRevoked {
		t.Fatalf("VerifyNotification() = %#v", notification)
	}
}

func TestAppleVerifierRejectsProductionNotificationForAnotherApp(t *testing.T) {
	fixture := newAppleCertificateFixture(t)
	_, privateKeyPEM := newAPISigningKey(t)
	now := time.Date(2026, time.July, 14, 19, 0, 0, 0, time.UTC)
	signedNotification := fixture.signTransaction(t, map[string]any{
		"notificationType": "TEST",
		"notificationUUID": "33333333-3333-4333-8333-333333333333",
		"version":          "2.0",
		"signedDate":       now.UnixMilli(),
		"data": map[string]any{
			"bundleId": "com.clovery.app", "environment": "Production",
			"appAppleId": 999999999,
		},
	})
	verifier := newTestAppleVerifier(t, fixture.rootDER, privateKeyPEM, appleHTTPDoer(nil), now)

	_, err := verifier.VerifyNotification(context.Background(), signedNotification)
	if !errors.Is(err, ErrVerificationFailed) {
		t.Fatalf("VerifyNotification() wrong appAppleId error = %v", err)
	}
}

func TestAppleVerifierRejectsProductionSummaryForAnotherApp(t *testing.T) {
	fixture := newAppleCertificateFixture(t)
	_, privateKeyPEM := newAPISigningKey(t)
	now := time.Date(2026, time.July, 14, 19, 0, 0, 0, time.UTC)
	signedNotification := fixture.signTransaction(t, map[string]any{
		"notificationType": "RENEWAL_EXTENSION",
		"subtype":          "SUMMARY",
		"notificationUUID": "33333333-3333-4333-8333-333333333333",
		"version":          "2.0",
		"signedDate":       now.UnixMilli(),
		"summary": map[string]any{
			"bundleId": "com.another.app", "environment": "Production",
			"appAppleId": 1234567890,
		},
	})
	verifier := newTestAppleVerifier(t, fixture.rootDER, privateKeyPEM, appleHTTPDoer(nil), now)

	_, err := verifier.VerifyNotification(context.Background(), signedNotification)
	if !errors.Is(err, ErrVerificationFailed) {
		t.Fatalf("VerifyNotification() wrong summary app error = %v", err)
	}
}

func TestAppleVerifierAcceptsSignedTestNotificationWithoutTransaction(t *testing.T) {
	fixture := newAppleCertificateFixture(t)
	_, privateKeyPEM := newAPISigningKey(t)
	now := time.Date(2026, time.July, 14, 19, 0, 0, 0, time.UTC)
	signedNotification := fixture.signTransaction(t, map[string]any{
		"notificationType": "TEST",
		"notificationUUID": "33333333-3333-4333-8333-333333333333",
		"version":          "2.0",
		"signedDate":       now.UnixMilli(),
	})
	verifier := newTestAppleVerifier(t, fixture.rootDER, privateKeyPEM, appleHTTPDoer(nil), now)

	notification, err := verifier.VerifyNotification(context.Background(), signedNotification)
	if err != nil || notification.Transaction != nil {
		t.Fatalf("VerifyNotification() = %#v, error = %v", notification, err)
	}
}

func TestAppleVerifierAcceptsLegacyNotificationWithoutAccountToken(t *testing.T) {
	fixture := newAppleCertificateFixture(t)
	_, privateKeyPEM := newAPISigningKey(t)
	now := time.Date(2026, time.July, 14, 19, 0, 0, 0, time.UTC)
	transactionPayload := appleTransactionPayload(now)
	delete(transactionPayload, "appAccountToken")
	signedNotification := fixture.signTransaction(t, map[string]any{
		"notificationType": "DID_RENEW",
		"notificationUUID": "33333333-3333-4333-8333-333333333333",
		"version":          "2.0",
		"signedDate":       now.UnixMilli(),
		"data": map[string]any{
			"bundleId": "com.clovery.app", "environment": "Sandbox",
			"signedTransactionInfo": fixture.signTransaction(t, transactionPayload),
		},
	})
	verifier := newTestAppleVerifier(t, fixture.rootDER, privateKeyPEM, appleHTTPDoer(nil), now)

	notification, err := verifier.VerifyNotification(context.Background(), signedNotification)
	if err != nil || notification.Transaction == nil || notification.Transaction.AppAccountToken != "" {
		t.Fatalf("VerifyNotification() legacy notification = %#v, error = %v", notification, err)
	}
}
