package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base32"
	"errors"
	"fmt"
	"io"
	"strings"

	"github.com/clovery/clovery/services/api/internal/account"
)

var ErrInvalidRecoveryCode = errors.New("invalid or already used recovery code")

const recoveryCodeCount = 8

type RecoveryCodeService struct {
	database *sql.DB
	random   io.Reader
}

func NewRecoveryCodeService(database *sql.DB) *RecoveryCodeService {
	return &RecoveryCodeService{database: database, random: rand.Reader}
}

func (service *RecoveryCodeService) Replace(ctx context.Context, accountID string) ([]string, error) {
	transaction, err := service.database.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("begin recovery code replacement: %w", err)
	}
	defer func() { _ = transaction.Rollback() }()

	if _, err := transaction.ExecContext(
		ctx,
		"DELETE FROM recovery_codes WHERE account_id = $1",
		accountID,
	); err != nil {
		return nil, fmt.Errorf("delete prior recovery codes: %w", err)
	}

	codes := make([]string, 0, recoveryCodeCount)
	for range recoveryCodeCount {
		code, err := service.generateCode()
		if err != nil {
			return nil, err
		}
		codeID, err := randomUUID(service.random)
		if err != nil {
			return nil, fmt.Errorf("generate recovery code ID: %w", err)
		}
		codeHash := hashRecoveryCode(code)
		if _, err := transaction.ExecContext(
			ctx,
			"INSERT INTO recovery_codes (id, account_id, code_hash) VALUES ($1, $2, $3)",
			codeID,
			accountID,
			codeHash[:],
		); err != nil {
			return nil, fmt.Errorf("store recovery code: %w", err)
		}
		codes = append(codes, code)
	}

	if err := transaction.Commit(); err != nil {
		return nil, fmt.Errorf("commit recovery code replacement: %w", err)
	}
	return codes, nil
}

func (service *RecoveryCodeService) Consume(ctx context.Context, loginID string, code string) (string, error) {
	normalizedID, err := account.NormalizeLoginID(loginID)
	if err != nil {
		return "", ErrInvalidRecoveryCode
	}
	codeHash := hashRecoveryCode(code)

	var accountID string
	err = service.database.QueryRowContext(
		ctx,
		`WITH selected_code AS (
		    SELECT recovery_codes.id
		    FROM recovery_codes
		    JOIN account_login_ids
		      ON account_login_ids.account_id = recovery_codes.account_id
		    WHERE account_login_ids.normalized_id = $1
		      AND account_login_ids.status = 'active'
		      AND recovery_codes.code_hash = $2
		      AND recovery_codes.used_at IS NULL
		    LIMIT 1
		)
		UPDATE recovery_codes
		SET used_at = CURRENT_TIMESTAMP
		FROM selected_code
		WHERE recovery_codes.id = selected_code.id
		RETURNING recovery_codes.account_id`,
		normalizedID,
		codeHash[:],
	).Scan(&accountID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrInvalidRecoveryCode
	}
	if err != nil {
		return "", fmt.Errorf("consume recovery code: %w", err)
	}
	return accountID, nil
}

func (service *RecoveryCodeService) generateCode() (string, error) {
	randomBytes := make([]byte, 15)
	if _, err := io.ReadFull(service.random, randomBytes); err != nil {
		return "", fmt.Errorf("generate recovery code: %w", err)
	}
	encoded := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(randomBytes)
	return strings.Join([]string{
		encoded[0:6],
		encoded[6:12],
		encoded[12:18],
		encoded[18:24],
	}, "-"), nil
}

func hashRecoveryCode(code string) [sha256.Size]byte {
	normalizedCode := strings.ToUpper(strings.ReplaceAll(strings.TrimSpace(code), "-", ""))
	return sha256.Sum256([]byte(normalizedCode))
}
