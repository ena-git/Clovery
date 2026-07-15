package billing

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
)

var (
	ErrInvalidRequest          = errors.New("invalid billing request")
	ErrAccountMismatch         = errors.New("transaction account does not match authenticated account")
	ErrTransactionClaimed      = errors.New("transaction is already claimed by another account")
	ErrVerificationFailed      = errors.New("Apple transaction verification failed")
	ErrVerificationUnavailable = errors.New("Apple transaction verification is unavailable")
)

type Verifier interface {
	Verify(ctx context.Context, transactionID string, environment Environment) (VerifiedTransaction, error)
	VerifyNotification(ctx context.Context, signedPayload string) (AppleNotification, error)
	VerifyLegacyProof(
		ctx context.Context,
		signedTransactionInfo string,
		environment Environment,
	) (VerifiedTransaction, error)
	AssignAccountToken(
		ctx context.Context,
		originalTransactionID string,
		transactionID string,
		accountID string,
		environment Environment,
	) (VerifiedTransaction, error)
}

type repository interface {
	Record(
		ctx context.Context,
		accountID string,
		transaction VerifiedTransaction,
		now time.Time,
	) (Entitlement, error)
	List(ctx context.Context, accountID string) ([]Entitlement, error)
	RecordNotification(
		ctx context.Context,
		accountID string,
		notification AppleNotification,
		now time.Time,
	) error
	ReservePurchaseChain(
		ctx context.Context,
		accountID string,
		transaction VerifiedTransaction,
		now time.Time,
	) error
}

type Service struct {
	verifier   Verifier
	repository repository
	now        func() time.Time
}

func NewService(verifier Verifier, repository repository) (*Service, error) {
	if verifier == nil || repository == nil {
		return nil, fmt.Errorf("billing service dependencies are required")
	}
	return &Service{
		verifier: verifier, repository: repository,
		now: func() time.Time { return time.Now().UTC() },
	}, nil
}

func (service *Service) Verify(
	ctx context.Context,
	accountID string,
	transactionID string,
	environment Environment,
) (Entitlement, error) {
	accountUUID, err := uuid.Parse(accountID)
	transactionID = strings.TrimSpace(transactionID)
	if err != nil || transactionID == "" || len(transactionID) > 128 || !environment.Valid() {
		return Entitlement{}, ErrInvalidRequest
	}
	transaction, err := service.verifier.Verify(ctx, transactionID, environment)
	if err != nil {
		return Entitlement{}, err
	}
	transactionAccountID, err := uuid.Parse(transaction.AppAccountToken)
	if err != nil || transaction.TransactionID != transactionID || transaction.Environment != environment ||
		transaction.ProductID == "" || !transaction.Status.Valid() {
		return Entitlement{}, ErrVerificationFailed
	}
	if transactionAccountID != accountUUID {
		return Entitlement{}, ErrAccountMismatch
	}
	transaction.AppAccountToken = transactionAccountID.String()
	transaction.Status = transaction.stateAt(service.now())
	return service.repository.Record(ctx, accountUUID.String(), transaction, service.now())
}

func (service *Service) Restore(
	ctx context.Context,
	accountID string,
	transactionIDs []string,
	environment Environment,
) ([]Entitlement, error) {
	if len(transactionIDs) == 0 || len(transactionIDs) > 100 {
		return nil, ErrInvalidRequest
	}
	seen := make(map[string]struct{}, len(transactionIDs))
	for _, transactionID := range transactionIDs {
		if _, duplicate := seen[transactionID]; duplicate {
			continue
		}
		seen[transactionID] = struct{}{}
		if _, err := service.Verify(ctx, accountID, transactionID, environment); err != nil {
			return nil, err
		}
	}
	return service.List(ctx, accountID)
}

func (service *Service) List(ctx context.Context, accountID string) ([]Entitlement, error) {
	accountUUID, err := uuid.Parse(accountID)
	if err != nil {
		return nil, ErrInvalidRequest
	}
	entitlements, err := service.repository.List(ctx, accountUUID.String())
	if err != nil {
		return nil, err
	}
	if entitlements == nil {
		entitlements = make([]Entitlement, 0)
	}
	now := service.now()
	for index := range entitlements {
		if entitlements[index].RevokedAt != nil {
			entitlements[index].State = StateRevoked
			continue
		}
		if entitlements[index].ExpiresAt != nil && !entitlements[index].ExpiresAt.After(now) &&
			entitlements[index].State == StateActive {
			entitlements[index].State = StateExpired
		}
	}
	return entitlements, nil
}
