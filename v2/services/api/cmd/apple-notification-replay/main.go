package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
)

func main() {
	options, err := parseReplayOptions(os.Args[1:])
	if err != nil {
		slog.Error("parse Apple notification replay options", "error", err)
		os.Exit(2)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	processed, err := replayNotificationHistory(ctx, options)
	if err != nil {
		slog.Error("replay Apple notification history", "error", err, "processed", processed)
		os.Exit(1)
	}
	slog.Info("Apple notification history replay complete", "processed", processed)
}
