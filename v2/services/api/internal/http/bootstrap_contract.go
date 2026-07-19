package httpapi

import (
	"context"
	"time"
)

type BootstrapStatus struct {
	Status        string          `json:"status"`
	SourceKind    string          `json:"source_kind"`
	MigrationID   *string         `json:"migration_id"`
	Stages        BootstrapStages `json:"stages"`
	LastErrorCode *string         `json:"last_error_code"`
	RetryCount    int             `json:"retry_count"`
	UpdatedAt     time.Time       `json:"updated_at"`
}

type BootstrapStages struct {
	Identity    string `json:"identity"`
	Migration   string `json:"migration"`
	Entitlement string `json:"entitlement"`
	Vault       string `json:"vault"`
}

type BootstrapHTTPApplication interface {
	GetBootstrap(ctx context.Context, accountID string) (BootstrapStatus, error)
	ResumeBootstrap(
		ctx context.Context,
		accountID string,
		vaultID string,
		sourceKind string,
	) (BootstrapStatus, error)
}

type bootstrapResumeRequest struct {
	SourceKind string `json:"source_kind"`
}
