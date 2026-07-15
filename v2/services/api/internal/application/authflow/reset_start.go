package authflow

import "context"

type PasswordResetStartResult struct {
	Accepted  bool
	ExpiresIn int
}

func (service *Service) StartPasswordReset(
	_ context.Context,
	_ string,
	recoveryMethod string,
) (PasswordResetStartResult, error) {
	if recoveryMethod != "recovery_code" {
		return PasswordResetStartResult{}, ErrUnsupportedRecoveryMethod
	}
	return PasswordResetStartResult{Accepted: true, ExpiresIn: 600}, nil
}
