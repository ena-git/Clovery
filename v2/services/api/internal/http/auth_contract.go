package httpapi

import "context"

type AuthApplication interface {
	Register(context.Context, CreateAccountCommand) (AuthSession, error)
	Login(context.Context, PasswordLoginCommand) (AuthSession, error)
	StartPasswordReset(context.Context, PasswordResetStartCommand) (PasswordResetStartResult, error)
	CompletePasswordReset(context.Context, PasswordResetCompleteCommand) error
	ReplaceRecoveryCodes(context.Context, string, string) ([]string, error)
	ConsumeRecoveryCode(context.Context, RecoveryCodeConsumeCommand) (RecoveryProof, error)
}

type CreateAccountCommand struct {
	LoginID               string        `json:"login_id"`
	Password              string        `json:"password"`
	RecoveryMethod        string        `json:"recovery_method"`
	IdentityClaimToken    *string       `json:"identity_claim_token"`
	RegistrationRequestID *string       `json:"registration_request_id"`
	SourceKind            *string       `json:"source_kind"`
	Device                DeviceCommand `json:"device"`
}

type DeviceCommand struct {
	DeviceID    string `json:"device_id"`
	Platform    string `json:"platform"`
	DisplayName string `json:"display_name"`
}

type DeviceRegistration = DeviceCommand

type PasswordLoginCommand struct {
	LoginID  string             `json:"login_id"`
	Password string             `json:"password"`
	Device   DeviceRegistration `json:"device"`
}

type PasswordResetStartCommand struct {
	LoginID        string `json:"login_id"`
	RecoveryMethod string `json:"recovery_method"`
}

type PasswordResetStartResult struct {
	Accepted      bool   `json:"accepted"`
	ResetIntentID string `json:"reset_intent_id,omitempty"`
	Challenge     string `json:"challenge,omitempty"`
	ExpiresIn     int    `json:"expires_in"`
}

type PasswordResetCompleteCommand struct {
	ResetIntentID string `json:"reset_intent_id"`
	Proof         string `json:"proof"`
	NewPassword   string `json:"new_password"`
}

type RecoveryCodeConsumeCommand struct {
	LoginID      string `json:"login_id"`
	RecoveryCode string `json:"recovery_code"`
}

type RecoveryProof struct {
	ResetIntentID string `json:"reset_intent_id"`
	Proof         string `json:"recovery_proof"`
	ExpiresIn     int    `json:"expires_in"`
}

type AuthSession struct {
	AccountID            string   `json:"account_id"`
	VaultID              string   `json:"vault_id"`
	AccessToken          string   `json:"access_token"`
	AccessTokenExpiresIn int      `json:"access_token_expires_in"`
	RefreshToken         string   `json:"refresh_token"`
	RecoveryCodes        []string `json:"recovery_codes,omitempty"`
}
