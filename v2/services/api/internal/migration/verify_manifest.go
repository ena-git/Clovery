package migration

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"fmt"
	"strings"
)

func verifyStoredManifest(
	ctx context.Context,
	transaction *sql.Tx,
	vaultID string,
	migrationID string,
) error {
	var manifestBytes []byte
	var expectedDigest string
	if err := transaction.QueryRowContext(
		ctx,
		"SELECT manifest_bytes, manifest_sha256 FROM vault_migrations WHERE id = $1 AND vault_id = $2",
		migrationID,
		vaultID,
	).Scan(&manifestBytes, &expectedDigest); err != nil {
		return fmt.Errorf("load migration manifest integrity: %w", err)
	}
	digest := sha256.Sum256(manifestBytes)
	if !strings.EqualFold(hex.EncodeToString(digest[:]), expectedDigest) {
		return ErrIntegrityMismatch
	}
	return nil
}
