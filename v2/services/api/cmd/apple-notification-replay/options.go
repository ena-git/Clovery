package main

import (
	"flag"
	"fmt"
	"io"
	"time"

	"github.com/clovery/clovery/services/api/internal/billing"
)

type replayOptions struct {
	query billing.NotificationHistoryQuery
}

func parseReplayOptions(arguments []string) (replayOptions, error) {
	flags := flag.NewFlagSet("apple-notification-replay", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	var environment, start, end string
	var onlyFailures bool
	flags.StringVar(&environment, "environment", "", "production or sandbox")
	flags.StringVar(&start, "start", "", "RFC3339 start time")
	flags.StringVar(&end, "end", "", "RFC3339 end time")
	flags.BoolVar(&onlyFailures, "only-failures", true, "request only failed deliveries")
	if err := flags.Parse(arguments); err != nil || flags.NArg() != 0 {
		return replayOptions{}, fmt.Errorf("usage: apple-notification-replay --environment <production|sandbox> --start <RFC3339> --end <RFC3339>")
	}
	billingEnvironment := billing.Environment(environment)
	startAt, startErr := time.Parse(time.RFC3339, start)
	endAt, endErr := time.Parse(time.RFC3339, end)
	if !billingEnvironment.Valid() || startErr != nil || endErr != nil || !startAt.Before(endAt) {
		return replayOptions{}, fmt.Errorf("invalid notification history range or environment")
	}
	maximumWindow := 180 * 24 * time.Hour
	if billingEnvironment == billing.EnvironmentSandbox {
		maximumWindow = 30 * 24 * time.Hour
	}
	if endAt.Sub(startAt) > maximumWindow {
		return replayOptions{}, fmt.Errorf("notification history range exceeds Apple retention window")
	}
	return replayOptions{query: billing.NotificationHistoryQuery{
		StartAt: startAt.UTC(), EndAt: endAt.UTC(), Environment: billingEnvironment,
		OnlyFailures: onlyFailures,
	}}, nil
}
