package billing

import (
	"context"
	"encoding/hex"
	"strings"

	"github.com/google/uuid"
)

const maximumAppleNotificationSize = 1024 * 1024

func (service *Service) ProcessAppleNotification(ctx context.Context, signedPayload string) error {
	signedPayload = strings.TrimSpace(signedPayload)
	if signedPayload == "" || len(signedPayload) > maximumAppleNotificationSize {
		return ErrInvalidRequest
	}
	notification, err := service.verifier.VerifyNotification(ctx, signedPayload)
	if err != nil {
		return err
	}
	if !validAppleNotification(notification) {
		return ErrVerificationFailed
	}
	if notification.Transaction == nil {
		return service.repository.RecordNotification(ctx, "", notification, service.now())
	}
	transaction := *notification.Transaction
	if transaction.Environment != notification.Environment ||
		transaction.TransactionID == "" || transaction.ProductID == "" || !transaction.Status.Valid() {
		return ErrVerificationFailed
	}
	if transaction.AppAccountToken == "" {
		transaction.Status = transaction.stateAt(service.now())
		notification.Transaction = &transaction
		return service.repository.RecordNotification(ctx, "", notification, service.now())
	}
	accountID, err := uuid.Parse(transaction.AppAccountToken)
	if err != nil {
		return ErrVerificationFailed
	}
	transaction.AppAccountToken = accountID.String()
	transaction.Status = transaction.stateAt(service.now())
	notification.Transaction = &transaction
	return service.repository.RecordNotification(
		ctx, accountID.String(), notification, service.now(),
	)
}

func validAppleNotification(notification AppleNotification) bool {
	if _, err := uuid.Parse(notification.ID); err != nil || strings.TrimSpace(notification.Type) == "" ||
		notification.SignedAt.IsZero() || len(notification.PayloadSHA256) != 64 {
		return false
	}
	_, err := hex.DecodeString(notification.PayloadSHA256)
	if err != nil {
		return false
	}
	return notification.Transaction == nil || notification.Environment.Valid()
}
