package auth

import (
	"crypto/rand"
	"database/sql"
	"io"
)

type PostgresPasskeyStore struct {
	database *sql.DB
	cipher   *PasskeyCredentialCipher
	random   io.Reader
}

func NewPostgresPasskeyStore(
	database *sql.DB,
	credentialCipher *PasskeyCredentialCipher,
) *PostgresPasskeyStore {
	return &PostgresPasskeyStore{
		database: database,
		cipher:   credentialCipher,
		random:   rand.Reader,
	}
}
