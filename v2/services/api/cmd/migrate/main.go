package main

import (
	"fmt"
	"log/slog"
	"os"
	"strings"

	"github.com/clovery/clovery/services/api/internal/database"
)

func main() {
	direction, err := parseDirection(os.Args[1:])
	if err != nil {
		slog.Error("parse migration direction", "error", err)
		os.Exit(2)
	}

	databaseURL := strings.TrimSpace(os.Getenv("DATABASE_URL"))
	if databaseURL == "" {
		slog.Error("DATABASE_URL is required")
		os.Exit(2)
	}
	migrationsPath := strings.TrimSpace(os.Getenv("MIGRATIONS_PATH"))
	if migrationsPath == "" {
		slog.Error("MIGRATIONS_PATH is required")
		os.Exit(2)
	}

	if err := database.Apply(databaseURL, migrationsPath, direction); err != nil {
		slog.Error("run database migrations", "error", err)
		os.Exit(1)
	}
	slog.Info("database migrations complete")
}

func parseDirection(arguments []string) (database.Direction, error) {
	if len(arguments) != 1 {
		return 0, fmt.Errorf("usage: migrate up")
	}

	switch arguments[0] {
	case "up":
		return database.Up, nil
	default:
		return 0, fmt.Errorf("unsupported migration direction %q", arguments[0])
	}
}
