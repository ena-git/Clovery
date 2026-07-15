package migration

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"sync"
	"testing"
	"time"
)

const (
	postgresAssetAccountID = "11111111-1111-4111-8111-111111111111"
	postgresAssetVaultID   = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
	postgresAssetMigration = "22222222-2222-4222-8222-222222222222"
	postgresAssetID        = "33333333-3333-4333-8333-333333333333"
	postgresAssetFilename  = "photo-1.jpg"
	postgresAssetSHA256    = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	postgresAssetBytes     = int64(20)
)

func TestPostgresAddAssetAndVerifyRaceRemainsRecoverable(t *testing.T) {
	databaseHandle := openMigrationIntegrationDatabase(t)
	seedPostgresAssetMigration(t, databaseHandle, true)
	repository := NewPostgresRepository(databaseHandle)

	start := make(chan struct{})
	var waitGroup sync.WaitGroup
	waitGroup.Add(2)
	var addErr, verifyErr error
	go func() {
		defer waitGroup.Done()
		<-start
		addErr = repository.AddAsset(
			context.Background(), postgresAssetVaultID, postgresAssetMigration,
			postgresAssetID, postgresAssetFilename, postgresAssetBytes, postgresAssetSHA256,
		)
	}()
	go func() {
		defer waitGroup.Done()
		<-start
		_, verifyErr = repository.Verify(
			context.Background(), postgresAssetVaultID, postgresAssetMigration,
		)
	}()
	close(start)
	waitGroup.Wait()

	if addErr != nil {
		t.Fatalf("concurrent AddAsset() error = %v", addErr)
	}
	if verifyErr != nil && !errors.Is(verifyErr, ErrVerificationFailed) {
		t.Fatalf("concurrent Verify() error = %v", verifyErr)
	}
	finalReport, err := repository.Verify(
		context.Background(), postgresAssetVaultID, postgresAssetMigration,
	)
	if err != nil {
		t.Fatalf("final Verify() error = %v", err)
	}
	if finalReport.Status != "verified" || finalReport.VerifiedAssets != 1 ||
		finalReport.VerifiedBytes != postgresAssetBytes {
		t.Fatalf("final Verify() report = %#v", finalReport)
	}

	var stagedAssets int
	if err := databaseHandle.QueryRow(
		"SELECT COUNT(*) FROM migration_assets WHERE migration_id = $1",
		postgresAssetMigration,
	).Scan(&stagedAssets); err != nil || stagedAssets != 1 {
		t.Fatalf("staged assets = %d, error = %v", stagedAssets, err)
	}
}

func TestPostgresVerifyRejectsMissingManifestPhoto(t *testing.T) {
	databaseHandle := openMigrationIntegrationDatabase(t)
	seedPostgresAssetMigration(t, databaseHandle, false)
	repository := NewPostgresRepository(databaseHandle)

	report, err := repository.Verify(
		context.Background(), postgresAssetVaultID, postgresAssetMigration,
	)
	if !errors.Is(err, ErrVerificationFailed) {
		t.Fatalf("Verify() error = %v", err)
	}
	if report.ExpectedAssets != 1 || report.VerifiedAssets != 0 ||
		report.ExpectedBytes != postgresAssetBytes || report.VerifiedBytes != 0 {
		t.Fatalf("Verify() report = %#v", report)
	}

	persistedReport, err := repository.GetReport(
		context.Background(), postgresAssetVaultID, postgresAssetMigration,
	)
	if err != nil {
		t.Fatalf("GetReport() error = %v", err)
	}
	if persistedReport.Status != "uploading" ||
		!postgresReportHasError(t, persistedReport.Errors, "count_or_size_mismatch") {
		t.Fatalf("persisted report = %#v", persistedReport)
	}
}

func seedPostgresAssetMigration(t *testing.T, databaseHandle *sql.DB, includeCompletedAsset bool) {
	t.Helper()
	manifest := []byte(`{"format_version":1,"exported_at":"2026-07-15T00:00:00Z","entries_file":"entries.json","entries_sha256":"4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945","entry_count":0,"entries":[],"deleted_ids_file":"deleted_ids.json","deleted_ids_sha256":"4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945","deleted_count":0,"deleted_ids":[],"photos":[{"filename":"photo-1.jpg","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","bytes":20}],"sources":["localStorage"]}`)
	manifestDigest := sha256.Sum256(manifest)
	now := time.Now().UTC()

	if _, err := databaseHandle.Exec(
		"INSERT INTO clovery_accounts (id) VALUES ($1)", postgresAssetAccountID,
	); err != nil {
		t.Fatalf("seed migration account: %v", err)
	}
	if _, err := databaseHandle.Exec(
		"INSERT INTO vaults (id, owner_account_id, status) VALUES ($1, $2, 'active')",
		postgresAssetVaultID, postgresAssetAccountID,
	); err != nil {
		t.Fatalf("seed migration Vault: %v", err)
	}
	if _, err := databaseHandle.Exec(
		`INSERT INTO vault_migrations (
			id, vault_id, format_version, source, expected_entry_count, expected_deleted_count,
			expected_asset_count, expected_total_bytes, manifest_sha256, manifest, manifest_bytes,
			status, created_at
		) VALUES ($1, $2, 1, 'v1_bundle', 0, 0, 1, $3, $4, $5::jsonb, $6, 'uploading', $7)`,
		postgresAssetMigration, postgresAssetVaultID, postgresAssetBytes,
		hex.EncodeToString(manifestDigest[:]), string(manifest), manifest, now,
	); err != nil {
		t.Fatalf("seed asset migration: %v", err)
	}
	if !includeCompletedAsset {
		return
	}
	if _, err := databaseHandle.Exec(
		`INSERT INTO vault_assets (
			id, vault_id, object_key, content_type, byte_size, sha256,
			status, created_at, completed_at
		) VALUES ($1, $2, $3, 'image/jpeg', $4, $5, 'complete', $6, $6)`,
		postgresAssetID, postgresAssetVaultID, "migration/"+postgresAssetID,
		postgresAssetBytes, postgresAssetSHA256, now,
	); err != nil {
		t.Fatalf("seed completed migration asset: %v", err)
	}
}

func postgresReportHasError(t *testing.T, encoded json.RawMessage, expectedCode string) bool {
	t.Helper()
	var reportErrors []struct {
		Code string `json:"code"`
	}
	if err := json.Unmarshal(encoded, &reportErrors); err != nil {
		t.Fatalf("decode migration report errors: %v", err)
	}
	for _, reportError := range reportErrors {
		if reportError.Code == expectedCode {
			return true
		}
	}
	return false
}
