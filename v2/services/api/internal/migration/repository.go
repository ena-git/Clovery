package migration

import (
	"database/sql"
	"errors"
)

var ErrMigrationNotFound = errors.New("migration not found")

type PostgresRepository struct {
	database *sql.DB
}

func NewPostgresRepository(database *sql.DB) *PostgresRepository {
	return &PostgresRepository{database: database}
}
