package observability

type Counter string

const (
	MigrationStarted            Counter = "clovery_migration_started_total"
	MigrationCompleted          Counter = "clovery_migration_completed_total"
	MigrationFailed             Counter = "clovery_migration_failed_total"
	MigrationValidationMismatch Counter = "clovery_migration_validation_mismatch_total"
	SyncConflicts               Counter = "clovery_sync_conflicts_total"
	AuthenticationFailures      Counter = "clovery_authentication_failures_total"
	BindingFailures             Counter = "clovery_binding_failures_total"
	DeviceRevocations           Counter = "clovery_device_revocations_total"
	BillingRestores             Counter = "clovery_billing_restores_total"
)

type Gauge string

const SyncBacklog Gauge = "clovery_sync_backlog_operations"

var allowedCounters = []Counter{
	MigrationStarted,
	MigrationCompleted,
	MigrationFailed,
	MigrationValidationMismatch,
	SyncConflicts,
	AuthenticationFailures,
	BindingFailures,
	DeviceRevocations,
	BillingRestores,
}

var allowedGauges = []Gauge{SyncBacklog}

func validCounter(metric Counter) bool {
	for _, allowed := range allowedCounters {
		if metric == allowed {
			return true
		}
	}
	return false
}

func validGauge(metric Gauge) bool {
	for _, allowed := range allowedGauges {
		if metric == allowed {
			return true
		}
	}
	return false
}
