package main

import (
	"testing"

	"github.com/clovery/clovery/services/api/internal/billing"
)

func TestParseReplayOptionsRequiresBoundedExplicitRange(t *testing.T) {
	options, err := parseReplayOptions([]string{
		"--environment", "production",
		"--start", "2026-07-14T00:00:00Z",
		"--end", "2026-07-15T00:00:00Z",
		"--only-failures=false",
	})
	if err != nil {
		t.Fatalf("parseReplayOptions() error = %v", err)
	}
	if options.query.Environment != billing.EnvironmentProduction || options.query.OnlyFailures {
		t.Fatalf("parseReplayOptions() = %#v", options)
	}

	if _, err := parseReplayOptions([]string{
		"--environment", "sandbox",
		"--start", "2026-05-01T00:00:00Z",
		"--end", "2026-07-15T00:00:00Z",
	}); err == nil {
		t.Fatal("parseReplayOptions() accepted a sandbox range beyond 30 days")
	}
}
