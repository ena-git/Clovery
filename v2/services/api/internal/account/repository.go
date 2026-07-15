package account

import (
	"database/sql"
	"errors"

	"github.com/jackc/pgx/v5/pgconn"
)

var (
	ErrAccountNotFound      = errors.New("account not found")
	ErrIdentityAlreadyBound = errors.New("external identity is already bound")
	ErrInvalidLoginID       = errors.New("invalid Clovery ID")
	ErrLoginIDUnavailable   = errors.New("Clovery ID is unavailable")
)

type Repository struct {
	database *sql.DB
}

func NewRepository(database *sql.DB) *Repository {
	return &Repository{database: database}
}

func isConstraint(err error, constraintName string) bool {
	var postgresError *pgconn.PgError
	return errors.As(err, &postgresError) && postgresError.ConstraintName == constraintName
}
