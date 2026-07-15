package database

import (
	"errors"
	"fmt"
	"net/url"
	"path/filepath"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
)

type Direction uint8

const (
	Up Direction = iota
	Down
)

func Apply(databaseURL string, migrationsPath string, direction Direction) (resultErr error) {
	absolutePath, err := filepath.Abs(migrationsPath)
	if err != nil {
		return fmt.Errorf("resolve migrations path: %w", err)
	}

	sourceURL := (&url.URL{Scheme: "file", Path: absolutePath}).String()
	migrationRunner, err := migrate.New(sourceURL, databaseURL)
	if err != nil {
		return fmt.Errorf("initialize migration runner: %w", err)
	}
	defer func() {
		sourceErr, databaseErr := migrationRunner.Close()
		if resultErr == nil && sourceErr != nil {
			resultErr = fmt.Errorf("close migration source: %w", sourceErr)
		}
		if resultErr == nil && databaseErr != nil {
			resultErr = fmt.Errorf("close migration database: %w", databaseErr)
		}
	}()

	switch direction {
	case Up:
		err = migrationRunner.Up()
	case Down:
		err = migrationRunner.Steps(-1)
	default:
		return fmt.Errorf("unsupported migration direction: %d", direction)
	}

	if err != nil && !errors.Is(err, migrate.ErrNoChange) {
		return fmt.Errorf("apply database migration: %w", err)
	}
	return nil
}
