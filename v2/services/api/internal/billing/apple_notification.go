package billing

import (
	"context"
	"encoding/json"
	"strings"
	"time"

	"github.com/google/uuid"
)

type appleNotificationClaims struct {
	NotificationType string `json:"notificationType"`
	Subtype          string `json:"subtype"`
	NotificationUUID string `json:"notificationUUID"`
	Version          string `json:"version"`
	SignedDate       int64  `json:"signedDate"`
	Data             struct {
		BundleID              string `json:"bundleId"`
		AppAppleID            int64  `json:"appAppleId"`
		Environment           string `json:"environment"`
		Status                int    `json:"status"`
		SignedRenewalInfo     string `json:"signedRenewalInfo"`
		SignedTransactionInfo string `json:"signedTransactionInfo"`
	} `json:"data"`
	Summary appleNotificationAppMetadata `json:"summary"`
	AppData appleNotificationAppMetadata `json:"appData"`
}

func (verifier *AppleVerifier) VerifyNotification(
	_ context.Context,
	signedPayload string,
) (AppleNotification, error) {
	verified, err := verifier.verifyAppleJWS(strings.TrimSpace(signedPayload))
	if err != nil {
		return AppleNotification{}, err
	}
	var claims appleNotificationClaims
	if json.Unmarshal(verified.Payload, &claims) != nil || claims.Version != "2.0" ||
		strings.TrimSpace(claims.NotificationType) == "" || claims.SignedDate <= 0 {
		return AppleNotification{}, ErrVerificationFailed
	}
	notificationID, err := uuid.Parse(claims.NotificationUUID)
	if err != nil {
		return AppleNotification{}, ErrVerificationFailed
	}
	notification := AppleNotification{
		ID: notificationID.String(), Type: claims.NotificationType, Subtype: claims.Subtype,
		SignedAt: time.UnixMilli(claims.SignedDate), PayloadSHA256: verified.Hash,
	}
	metadata, hasMetadata, err := claims.notificationAppMetadata()
	if err != nil {
		return AppleNotification{}, err
	}
	if hasMetadata {
		environment, metadataErr := verifier.validateNotificationAppMetadata(metadata)
		if metadataErr != nil {
			return AppleNotification{}, metadataErr
		}
		notification.Environment = environment
	} else if claims.NotificationType != "TEST" {
		return AppleNotification{}, ErrVerificationFailed
	}
	if claims.Data.SignedTransactionInfo == "" {
		return notification, nil
	}
	environment := notification.Environment
	if !environment.Valid() {
		return AppleNotification{}, ErrVerificationFailed
	}
	transactionJWS, err := verifier.verifyAppleJWS(claims.Data.SignedTransactionInfo)
	if err != nil {
		return AppleNotification{}, err
	}
	var transactionClaims appleTransactionClaims
	if json.Unmarshal(transactionJWS.Payload, &transactionClaims) != nil {
		return AppleNotification{}, ErrVerificationFailed
	}
	transaction, err := verifier.transactionFromVerifiedJWSWithAccountToken(
		transactionJWS, transactionClaims.TransactionID, environment,
		"app_store_server_notification_v2", false,
	)
	if err != nil {
		return AppleNotification{}, err
	}
	if claims.Data.Status != 0 || claims.Data.SignedRenewalInfo != "" {
		if err := verifier.applyRenewalStatus(
			&transaction, claims.Data.Status, claims.Data.SignedRenewalInfo,
		); err != nil {
			return AppleNotification{}, err
		}
	}
	transaction.Metadata.SignedAt = notification.SignedAt
	notification.Transaction = &transaction
	return notification, nil
}

func parseAppleEnvironment(value string) (Environment, bool) {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case string(EnvironmentProduction):
		return EnvironmentProduction, true
	case string(EnvironmentSandbox):
		return EnvironmentSandbox, true
	default:
		return "", false
	}
}
