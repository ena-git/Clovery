package authflow

import (
	"context"
	"errors"
	"time"
)

var ErrRecentAuthenticationRequired = errors.New("recent authentication is required")

const recentAuthenticationMaximumAge = 5 * time.Minute

func (service *Service) ReplaceRecoveryCodes(
	ctx context.Context,
	accountID string,
	reauthenticationProof string,
) ([]string, error) {
	claims, err := service.sessions.AuthenticateRecent(
		ctx,
		reauthenticationProof,
		recentAuthenticationMaximumAge,
	)
	if err != nil || claims.AccountID != accountID {
		return nil, ErrRecentAuthenticationRequired
	}
	return service.recovery.Replace(ctx, accountID)
}

func (service *Service) ConsumeRecoveryCode(
	ctx context.Context,
	loginID string,
	code string,
) (RecoveryProof, error) {
	accountID, err := service.recovery.Consume(ctx, loginID, code)
	if err != nil {
		return RecoveryProof{}, err
	}
	proof, err := service.reset.CreateRecoveryProof(ctx, accountID)
	if err != nil {
		return RecoveryProof{}, err
	}
	return RecoveryProof{
		ResetIntentID: proof.ResetIntentID,
		Proof:         proof.Proof,
		ExpiresIn:     proof.ExpiresIn,
	}, nil
}

func (service *Service) CompletePasswordReset(
	ctx context.Context,
	intentID string,
	proof string,
	newPassword string,
) error {
	return service.reset.Complete(ctx, intentID, proof, newPassword)
}
