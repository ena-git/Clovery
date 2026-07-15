package authflow

type Device struct {
	ID          string
	Platform    string
	DisplayName string
}

type RegisterCommand struct {
	LoginID        string
	Password       string
	RecoveryMethod string
	Device         Device
}

type LoginCommand struct {
	LoginID  string
	Password string
	Device   Device
}

type SessionResult struct {
	AccountID            string
	VaultID              string
	AccessToken          string
	AccessTokenExpiresIn int
	RefreshToken         string
	RecoveryCodes        []string
}

type RecoveryProof struct {
	ResetIntentID string
	Proof         string
	ExpiresIn     int
}
