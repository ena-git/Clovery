package account

import "time"

type Profile struct {
	AccountID         string
	CloveryID         string
	Status            string
	CreatedAt         time.Time
	HasPassword       bool
	PasskeyCount      int
	RecoveryCodeCount int
	Bindings          []Binding
}

type Binding struct {
	Provider  string
	Issuer    string
	CreatedAt time.Time
}
