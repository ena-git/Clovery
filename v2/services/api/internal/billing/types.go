package billing

import "time"

type Environment string

const (
	EnvironmentProduction Environment = "production"
	EnvironmentSandbox    Environment = "sandbox"
)

func (environment Environment) Valid() bool {
	return environment == EnvironmentProduction || environment == EnvironmentSandbox
}

type State string

const (
	StateActive    State = "active"
	StateExpired   State = "expired"
	StateRevoked   State = "revoked"
	StateCancelled State = "cancelled"
	StateFailed    State = "failed"
)

func (state State) Valid() bool {
	switch state {
	case StateActive, StateExpired, StateRevoked, StateCancelled, StateFailed:
		return true
	default:
		return false
	}
}

type VerificationMetadata struct {
	Source            string    `json:"source"`
	SignedAt          time.Time `json:"signed_at"`
	JWSHash           string    `json:"jws_sha256"`
	CertificateSerial string    `json:"certificate_serial"`
}

type VerifiedTransaction struct {
	Storefront            string
	TransactionID         string
	OriginalTransactionID string
	ProductID             string
	Environment           Environment
	PurchaseAt            time.Time
	ExpiresAt             *time.Time
	RevokedAt             *time.Time
	AppAccountToken       string
	Status                State
	Metadata              VerificationMetadata
}

type AppleNotification struct {
	ID            string
	Type          string
	Subtype       string
	Environment   Environment
	SignedAt      time.Time
	PayloadSHA256 string
	Transaction   *VerifiedTransaction
}

func (transaction VerifiedTransaction) stateAt(now time.Time) State {
	if transaction.RevokedAt != nil {
		return StateRevoked
	}
	if transaction.Status == StateRevoked || transaction.Status == StateCancelled ||
		transaction.Status == StateFailed {
		return transaction.Status
	}
	if transaction.ExpiresAt != nil && !transaction.ExpiresAt.After(now) {
		return StateExpired
	}
	if transaction.Status == StateExpired {
		return StateExpired
	}
	return StateActive
}

type Entitlement struct {
	ProductID           string     `json:"product_id"`
	State               State      `json:"state"`
	ExpiresAt           *time.Time `json:"expires_at,omitempty"`
	RevokedAt           *time.Time `json:"revoked_at,omitempty"`
	SourceStorefront    string     `json:"source_storefront"`
	SourceTransactionID string     `json:"source_transaction_id"`
	UpdatedAt           time.Time  `json:"updated_at"`
}
