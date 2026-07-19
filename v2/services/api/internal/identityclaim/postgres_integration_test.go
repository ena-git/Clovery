package identityclaim

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/base64"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	cloverydatabase "github.com/clovery/clovery/services/api/internal/database"
	_ "github.com/jackc/pgx/v5/stdlib"
)

func TestPostgresIdentityClaims(t *testing.T) {
	databaseHandle := openIdentityClaimIntegrationDatabase(t)
	repository := NewPostgresRepository(databaseHandle)

	t.Run("stores digest without raw token", func(t *testing.T) {
		now := time.Now().UTC().Truncate(time.Microsecond)
		intentID := "11000000-0000-4000-8000-000000000001"
		seedIdentityClaimIntent(t, databaseHandle, intentID, "apple", now)
		service := integrationService(
			repository,
			bytes.Repeat([]byte{0x11}, 32),
			now,
			"12000000-0000-4000-8000-000000000001",
		)
		identity := Identity{
			Provider: "apple",
			Issuer:   "https://appleid.apple.com/exact",
			Subject:  "apple-subject-exact",
			IntentID: intentID,
		}

		issued, err := service.Issue(context.Background(), identity)
		if err != nil {
			t.Fatalf("Issue() error = %v", err)
		}
		rawToken, ok := issued.TakeToken()
		if !ok {
			t.Fatal("TakeToken() did not return the integration token")
		}
		if secondToken, secondOK := issued.TakeToken(); secondOK || secondToken != "" {
			t.Fatal("TakeToken() returned the integration token more than once")
		}
		var storedDigest string
		var provider string
		var issuer string
		var subject string
		var storedIntentID string
		var expiresAt time.Time
		if err := databaseHandle.QueryRow(`
			SELECT token_sha256, provider, issuer, subject, login_intent_id::text, expires_at
			FROM identity_claims
			WHERE id = $1
		`, "12000000-0000-4000-8000-000000000001").Scan(
			&storedDigest,
			&provider,
			&issuer,
			&subject,
			&storedIntentID,
			&expiresAt,
		); err != nil {
			t.Fatalf("load stored identity claim: %v", err)
		}
		if storedDigest != tokenSHA256(rawToken) || storedDigest == rawToken {
			t.Fatalf("stored digest = %q", storedDigest)
		}
		if len(storedDigest) != 64 || storedDigest != strings.ToLower(storedDigest) {
			t.Fatalf("stored digest format = %q", storedDigest)
		}
		if provider != identity.Provider || issuer != identity.Issuer ||
			subject != identity.Subject || storedIntentID != identity.IntentID {
			t.Fatalf(
				"stored identity provider=%q issuer=%q subject=%q intent=%q",
				provider,
				issuer,
				subject,
				storedIntentID,
			)
		}
		if !expiresAt.Equal(now.Add(10 * time.Minute)) {
			t.Fatalf("stored expiry = %v", expiresAt)
		}
		var rawTokenRows int
		if err := databaseHandle.QueryRow(`
			SELECT COUNT(*)
			FROM identity_claims
			WHERE token_sha256 = $1 OR issuer = $1 OR subject = $1
		`, rawToken).Scan(&rawTokenRows); err != nil {
			t.Fatalf("search raw token in identity claims: %v", err)
		}
		if rawTokenRows != 0 {
			t.Fatalf("raw token matched %d stored rows", rawTokenRows)
		}
	})

	t.Run("unknown token is invalid without disclosure", func(t *testing.T) {
		rawToken := base64.RawURLEncoding.EncodeToString(bytes.Repeat([]byte{0xee}, 32))
		transaction, err := databaseHandle.BeginTx(context.Background(), nil)
		if err != nil {
			t.Fatalf("begin unknown-token transaction: %v", err)
		}
		defer func() { _ = transaction.Rollback() }()

		_, err = repository.LockForRegistration(context.Background(), transaction, rawToken)
		if !errors.Is(err, ErrInvalidClaim) {
			t.Fatalf("LockForRegistration() error = %v, want ErrInvalidClaim", err)
		}
		if strings.Contains(err.Error(), rawToken) {
			t.Fatal("LockForRegistration() error contains raw token")
		}
	})

	t.Run("pending consumption is bound to its locking transaction", func(t *testing.T) {
		ctx := context.Background()
		now := time.Now().UTC().Truncate(time.Microsecond)
		intentID := "1f000000-0000-4000-8000-000000000001"
		claimID := "20000000-0000-4000-8000-000000000002"
		accountID := "21000000-0000-4000-8000-000000000001"
		vaultID := "22000000-0000-4000-8000-000000000001"
		requestID := "23000000-0000-4000-8000-000000000001"
		seedIdentityClaimIntent(t, databaseHandle, intentID, "huawei", now)
		service := integrationService(repository, bytes.Repeat([]byte{0x44}, 32), now, claimID)
		issued, err := service.Issue(ctx, Identity{
			Provider: "huawei",
			Issuer:   "https://oauth-login.cloud.huawei.com",
			Subject:  "transaction-bound-subject",
			IntentID: intentID,
		})
		if err != nil {
			t.Fatalf("issue transaction-bound claim: %v", err)
		}
		rawToken, ok := issued.TakeToken()
		if !ok {
			t.Fatal("TakeToken() did not return transaction-bound token")
		}
		if secondToken, secondOK := issued.TakeToken(); secondOK || secondToken != "" {
			t.Fatal("TakeToken() returned transaction-bound token more than once")
		}

		firstTransaction, err := databaseHandle.BeginTx(ctx, nil)
		if err != nil {
			t.Fatalf("begin capability transaction: %v", err)
		}
		defer func() { _ = firstTransaction.Rollback() }()
		locked, err := repository.LockForRegistration(ctx, firstTransaction, rawToken)
		if err != nil {
			t.Fatalf("lock capability claim: %v", err)
		}
		resolution, err := service.ResolveForRegistration(locked, requestID)
		if err != nil || resolution.PendingConsumption == nil {
			t.Fatalf("resolve capability claim = %#v, error = %v", resolution, err)
		}

		secondTransaction, err := databaseHandle.BeginTx(ctx, nil)
		if err != nil {
			t.Fatalf("begin mismatched capability transaction: %v", err)
		}
		defer func() { _ = secondTransaction.Rollback() }()
		if err := repository.MarkConsumed(
			ctx,
			secondTransaction,
			resolution.PendingConsumption,
			now,
			accountID,
			requestID,
		); !errors.Is(err, ErrInvalidClaim) {
			t.Fatalf("mismatched MarkConsumed() error = %v, want ErrInvalidClaim", err)
		}
		var remainsUnconsumed bool
		if err := databaseHandle.QueryRow(
			"SELECT consumed_at IS NULL FROM identity_claims WHERE id = $1",
			claimID,
		).Scan(&remainsUnconsumed); err != nil {
			t.Fatalf("check mismatched consumption state: %v", err)
		}
		if !remainsUnconsumed {
			t.Fatal("mismatched transaction consumed the claim")
		}
		if err := secondTransaction.Rollback(); err != nil {
			t.Fatalf("rollback mismatched capability transaction: %v", err)
		}

		if _, err := firstTransaction.ExecContext(ctx, "INSERT INTO clovery_accounts (id) VALUES ($1)", accountID); err != nil {
			t.Fatalf("insert capability account: %v", err)
		}
		if _, err := firstTransaction.ExecContext(
			ctx,
			"INSERT INTO vaults (id, owner_account_id, status) VALUES ($1, $2, 'active')",
			vaultID,
			accountID,
		); err != nil {
			t.Fatalf("insert capability vault: %v", err)
		}
		if err := repository.MarkConsumed(
			ctx,
			firstTransaction,
			resolution.PendingConsumption,
			now,
			accountID,
			requestID,
		); err != nil {
			t.Fatalf("matching MarkConsumed() error = %v", err)
		}
		if err := firstTransaction.Commit(); err != nil {
			t.Fatalf("commit capability transaction: %v", err)
		}
	})

	t.Run("row lock serializes same-request replay", func(t *testing.T) {
		fixture := concurrentClaimFixture{
			claimID:             "13000000-0000-4000-8000-000000000001",
			intentID:            "14000000-0000-4000-8000-000000000001",
			accountID:           "15000000-0000-4000-8000-000000000001",
			vaultID:             "16000000-0000-4000-8000-000000000001",
			registrationRequest: "17000000-0000-4000-8000-000000000001",
			randomByte:          0x22,
		}
		resolution, err := exerciseConcurrentClaim(t, databaseHandle, repository, fixture, fixture.registrationRequest)
		if err != nil {
			t.Fatalf("competing resolution error = %v", err)
		}
		if resolution.Existing == nil || resolution.Existing.AccountID != fixture.accountID ||
			resolution.Existing.VaultID != fixture.vaultID {
			t.Fatalf("same-request resolution = %#v", resolution)
		}
	})

	t.Run("row lock serializes different-request rejection", func(t *testing.T) {
		fixture := concurrentClaimFixture{
			claimID:             "18000000-0000-4000-8000-000000000001",
			intentID:            "19000000-0000-4000-8000-000000000001",
			accountID:           "1a000000-0000-4000-8000-000000000001",
			vaultID:             "1b000000-0000-4000-8000-000000000001",
			registrationRequest: "1c000000-0000-4000-8000-000000000001",
			randomByte:          0x33,
		}
		_, err := exerciseConcurrentClaim(
			t,
			databaseHandle,
			repository,
			fixture,
			"1d000000-0000-4000-8000-000000000001",
		)
		if !errors.Is(err, ErrConsumedClaim) {
			t.Fatalf("competing resolution error = %v, want ErrConsumedClaim", err)
		}
	})
}

type concurrentClaimFixture struct {
	claimID             string
	intentID            string
	accountID           string
	vaultID             string
	registrationRequest string
	randomByte          byte
}

type lockedClaimResult struct {
	claim *LockedClaim
	err   error
}

func exerciseConcurrentClaim(
	t *testing.T,
	databaseHandle *sql.DB,
	repository *PostgresRepository,
	fixture concurrentClaimFixture,
	competingRequestID string,
) (RegistrationResolution, error) {
	t.Helper()
	ctx := context.Background()
	now := time.Now().UTC().Truncate(time.Microsecond)
	seedIdentityClaimIntent(t, databaseHandle, fixture.intentID, "google", now)
	service := integrationService(
		repository,
		bytes.Repeat([]byte{fixture.randomByte}, 32),
		now,
		fixture.claimID,
	)
	issued, err := service.Issue(ctx, Identity{
		Provider: "google",
		Issuer:   "https://accounts.google.com",
		Subject:  "subject-" + fixture.claimID,
		IntentID: fixture.intentID,
	})
	if err != nil {
		t.Fatalf("issue concurrent claim: %v", err)
	}
	rawToken, ok := issued.TakeToken()
	if !ok {
		t.Fatal("TakeToken() did not return the concurrent token")
	}
	if secondToken, secondOK := issued.TakeToken(); secondOK || secondToken != "" {
		t.Fatal("TakeToken() returned the concurrent token more than once")
	}

	firstTransaction, err := databaseHandle.BeginTx(ctx, nil)
	if err != nil {
		t.Fatalf("begin first transaction: %v", err)
	}
	defer func() { _ = firstTransaction.Rollback() }()
	firstLocked, err := repository.LockForRegistration(ctx, firstTransaction, rawToken)
	if err != nil {
		t.Fatalf("lock claim in first transaction: %v", err)
	}
	firstResolution, err := service.ResolveForRegistration(firstLocked, fixture.registrationRequest)
	if err != nil || firstResolution.Existing != nil {
		t.Fatalf("first resolution = %#v, error = %v", firstResolution, err)
	}

	secondTransaction, err := databaseHandle.BeginTx(ctx, nil)
	if err != nil {
		t.Fatalf("begin second transaction: %v", err)
	}
	defer func() { _ = secondTransaction.Rollback() }()
	if _, err := secondTransaction.ExecContext(ctx, "SET LOCAL lock_timeout = '5s'"); err != nil {
		t.Fatalf("set competing lock timeout: %v", err)
	}
	var secondBackendPID int
	if err := secondTransaction.QueryRowContext(ctx, "SELECT pg_backend_pid()").Scan(&secondBackendPID); err != nil {
		t.Fatalf("load competing backend PID: %v", err)
	}
	observerConnection, err := databaseHandle.Conn(ctx)
	if err != nil {
		t.Fatalf("open lock observer connection: %v", err)
	}
	defer func() { _ = observerConnection.Close() }()
	lockResult := make(chan lockedClaimResult, 1)
	go func() {
		claim, lockErr := repository.LockForRegistration(ctx, secondTransaction, rawToken)
		lockResult <- lockedClaimResult{claim: claim, err: lockErr}
	}()
	waitForBackendLock(t, observerConnection, secondBackendPID, 4*time.Second)

	if _, err := firstTransaction.ExecContext(ctx, "INSERT INTO clovery_accounts (id) VALUES ($1)", fixture.accountID); err != nil {
		t.Fatalf("insert claimed account: %v", err)
	}
	if _, err := firstTransaction.ExecContext(
		ctx,
		"INSERT INTO vaults (id, owner_account_id, status) VALUES ($1, $2, 'active')",
		fixture.vaultID,
		fixture.accountID,
	); err != nil {
		t.Fatalf("insert claimed vault: %v", err)
	}
	if err := repository.MarkConsumed(
		ctx,
		firstTransaction,
		firstResolution.PendingConsumption,
		now,
		fixture.accountID,
		fixture.registrationRequest,
	); err != nil {
		t.Fatalf("mark claim consumed in first transaction: %v", err)
	}
	if err := firstTransaction.Commit(); err != nil {
		t.Fatalf("commit first transaction: %v", err)
	}

	var competing lockedClaimResult
	select {
	case competing = <-lockResult:
	case <-time.After(6 * time.Second):
		t.Fatal("competing lock did not finish after first commit")
	}
	if competing.err != nil {
		t.Fatalf("competing lock error = %v", competing.err)
	}
	resolution, resolutionErr := service.ResolveForRegistration(competing.claim, competingRequestID)
	if err := repository.MarkConsumed(
		ctx,
		secondTransaction,
		firstResolution.PendingConsumption,
		now.Add(time.Second),
		"1e000000-0000-4000-8000-000000000001",
		competingRequestID,
	); !errors.Is(err, ErrInvalidClaim) {
		t.Fatalf("competing MarkConsumed() error = %v, want ErrInvalidClaim", err)
	}
	if err := secondTransaction.Commit(); err != nil {
		t.Fatalf("commit second transaction: %v", err)
	}

	var accountCount int
	var vaultCount int
	var consumedCount int
	if err := databaseHandle.QueryRow(
		"SELECT COUNT(*) FROM clovery_accounts WHERE id = $1",
		fixture.accountID,
	).Scan(&accountCount); err != nil {
		t.Fatalf("count claimed accounts: %v", err)
	}
	if err := databaseHandle.QueryRow(
		"SELECT COUNT(*) FROM vaults WHERE id = $1 AND owner_account_id = $2",
		fixture.vaultID,
		fixture.accountID,
	).Scan(&vaultCount); err != nil {
		t.Fatalf("count claimed vaults: %v", err)
	}
	if err := databaseHandle.QueryRow(`
		SELECT COUNT(*)
		FROM identity_claims
		WHERE id = $1
		  AND consumed_by_account_id = $2
		  AND registration_request_id = $3
	`, fixture.claimID, fixture.accountID, fixture.registrationRequest).Scan(&consumedCount); err != nil {
		t.Fatalf("count consumed claims: %v", err)
	}
	if accountCount != 1 || vaultCount != 1 || consumedCount != 1 {
		t.Fatalf("ownership counts account=%d vault=%d consumed=%d", accountCount, vaultCount, consumedCount)
	}
	return resolution, resolutionErr
}

func waitForBackendLock(
	t *testing.T,
	observerConnection *sql.Conn,
	backendPID int,
	timeout time.Duration,
) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	var lastState string
	var lastWaitEventType string
	var lastWaitEvent string
	var lastQuery string
	var lastBlockingPIDs string
	for {
		err := observerConnection.QueryRowContext(context.Background(), `
			SELECT state,
			       COALESCE(wait_event_type, ''),
			       COALESCE(wait_event, ''),
			       query,
			       pg_blocking_pids(pid)::text
			FROM pg_stat_activity
			WHERE pid = $1
		`, backendPID).Scan(
			&lastState,
			&lastWaitEventType,
			&lastWaitEvent,
			&lastQuery,
			&lastBlockingPIDs,
		)
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			t.Fatalf("observe competing backend lock: %v", err)
		}
		if err == nil && lastWaitEventType == "Lock" {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf(
				"backend %d did not enter Lock wait: state=%q wait_event_type=%q wait_event=%q blocking_pids=%q query=%q",
				backendPID,
				lastState,
				lastWaitEventType,
				lastWaitEvent,
				lastBlockingPIDs,
				lastQuery,
			)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func integrationService(
	repository IssueRepository,
	randomBytes []byte,
	now time.Time,
	claimID string,
) *Service {
	return &Service{
		repository:   repository,
		randomSource: bytes.NewReader(randomBytes),
		now:          func() time.Time { return now },
		newID:        func() string { return claimID },
	}
}

func seedIdentityClaimIntent(
	t *testing.T,
	databaseHandle *sql.DB,
	intentID string,
	provider string,
	now time.Time,
) {
	t.Helper()
	if _, err := databaseHandle.Exec(`
		INSERT INTO federation_intents (
			id, purpose, provider, nonce_hash, created_at, expires_at, used_at
		) VALUES ($1, 'login', $2, decode(repeat('00', 32), 'hex'), $3, $4, $3)
	`, intentID, provider, now.Add(-time.Minute), now.Add(time.Hour)); err != nil {
		t.Fatalf("seed federation intent: %v", err)
	}
}

func openIdentityClaimIntegrationDatabase(t *testing.T) *sql.DB {
	t.Helper()
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		t.Skip("DATABASE_URL is required for identity claim integration tests")
	}
	schemaName := fmt.Sprintf("clovery_identityclaim_%d_%d", os.Getpid(), time.Now().UnixNano())
	adminDatabase, err := sql.Open("pgx", databaseURL)
	if err != nil {
		t.Fatalf("open identity claim admin database: %v", err)
	}
	t.Cleanup(func() { _ = adminDatabase.Close() })
	if _, err := adminDatabase.Exec("CREATE SCHEMA " + schemaName); err != nil {
		t.Fatalf("create identity claim schema: %v", err)
	}
	t.Cleanup(func() { _, _ = adminDatabase.Exec("DROP SCHEMA IF EXISTS " + schemaName + " CASCADE") })

	schemaURL := identityClaimDatabaseURL(t, databaseURL, schemaName)
	if err := cloverydatabase.Apply(schemaURL, identityClaimMigrationsPath(t), cloverydatabase.Up); err != nil {
		t.Fatalf("apply identity claim migrations: %v", err)
	}
	databaseHandle, err := sql.Open("pgx", schemaURL)
	if err != nil {
		t.Fatalf("open migrated identity claim database: %v", err)
	}
	t.Cleanup(func() { _ = databaseHandle.Close() })
	if err := databaseHandle.Ping(); err != nil {
		t.Fatalf("ping identity claim database: %v", err)
	}
	return databaseHandle
}

func identityClaimDatabaseURL(t *testing.T, databaseURL string, schemaName string) string {
	t.Helper()
	parsed, err := url.Parse(databaseURL)
	if err != nil {
		t.Fatalf("parse identity claim database URL: %v", err)
	}
	query := parsed.Query()
	query.Set("search_path", schemaName)
	parsed.RawQuery = query.Encode()
	return parsed.String()
}

func identityClaimMigrationsPath(t *testing.T) string {
	t.Helper()
	_, currentFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("resolve identity claim integration test path")
	}
	return filepath.Join(filepath.Dir(currentFile), "..", "..", "migrations")
}
