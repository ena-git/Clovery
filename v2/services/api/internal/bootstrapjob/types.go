package bootstrapjob

import (
	"errors"
	"time"
)

var (
	ErrNotFound           = errors.New("bootstrap job not found")
	ErrConflict           = errors.New("bootstrap job conflict")
	ErrInvalidRequest     = errors.New("invalid bootstrap request")
	ErrInvalidSourceKind  = errors.New("invalid bootstrap source kind")
	ErrInvalidStageState  = errors.New("invalid bootstrap stage state")
	ErrInvalidErrorCode   = errors.New("invalid bootstrap error code")
	ErrInvalidMigrationID = errors.New("invalid bootstrap migration ID")
	ErrInvalidTransition  = errors.New("invalid bootstrap transition")
)

type SourceKind string

const (
	SourceNewInstall     SourceKind = "new_install"
	SourceLegacyLocal    SourceKind = "legacy_local"
	SourceLegacyCloudKit SourceKind = "legacy_cloudkit"
)

func (source SourceKind) Valid() bool {
	switch source {
	case SourceNewInstall, SourceLegacyLocal, SourceLegacyCloudKit:
		return true
	default:
		return false
	}
}

type StageState string

const (
	StagePending        StageState = "pending"
	StageComplete       StageState = "complete"
	StageNeedsAttention StageState = "needs_attention"
)

func (state StageState) Valid() bool {
	switch state {
	case StagePending, StageComplete, StageNeedsAttention:
		return true
	default:
		return false
	}
}

type Status string

const (
	StatusPending        Status = "pending"
	StatusRunning        Status = "running"
	StatusNeedsAttention Status = "needs_attention"
	StatusComplete       Status = "complete"
)

type Job struct {
	AccountID        string
	VaultID          string
	SourceKind       SourceKind
	MigrationID      *string
	IdentityState    StageState
	MigrationState   StageState
	EntitlementState StageState
	VaultState       StageState
	Status           Status
	LastErrorCode    *string
	RetryCount       int
	UpdatedAt        time.Time
}
