package auth

import (
	"context"
	"errors"
	"testing"
)

func TestRecoveryCodesAreOneTimeAndStoredOnlyAsHashes(t *testing.T) {
	databaseHandle := openAuthTestDatabase(t)
	loginService, err := NewLoginService(databaseHandle)
	if err != nil {
		t.Fatalf("create login service: %v", err)
	}
	ctx := context.Background()
	registration := Registration{
		AccountID: "66666666-6666-4666-8666-666666666666",
		VaultID:   "99999999-9999-4999-8999-999999999999",
		LoginID:   "recovery_user",
		Password:  "four quiet words together",
	}
	if err := loginService.Register(ctx, registration); err != nil {
		t.Fatalf("register recovery account: %v", err)
	}

	service := NewRecoveryCodeService(databaseHandle)
	codes, err := service.Replace(ctx, registration.AccountID)
	if err != nil {
		t.Fatalf("replace recovery codes: %v", err)
	}
	if len(codes) != 8 {
		t.Fatalf("recovery code count = %d", len(codes))
	}
	seen := make(map[string]struct{}, len(codes))
	for _, code := range codes {
		if _, duplicate := seen[code]; duplicate {
			t.Fatalf("duplicate recovery code %q", code)
		}
		seen[code] = struct{}{}
	}

	var rawCodeMatches int
	if err := databaseHandle.QueryRowContext(
		ctx,
		"SELECT COUNT(*) FROM recovery_codes WHERE encode(code_hash, 'hex') = $1",
		codes[0],
	).Scan(&rawCodeMatches); err != nil {
		t.Fatalf("inspect stored recovery code: %v", err)
	}
	if rawCodeMatches != 0 {
		t.Fatal("recovery code was stored in plaintext")
	}

	accountID, err := service.Consume(ctx, "RECOVERY_USER", codes[0])
	if err != nil {
		t.Fatalf("consume recovery code: %v", err)
	}
	if accountID != registration.AccountID {
		t.Fatalf("recovered account ID = %q", accountID)
	}
	if _, err := service.Consume(ctx, "recovery_user", codes[0]); !errors.Is(err, ErrInvalidRecoveryCode) {
		t.Fatalf("reused recovery code error = %v", err)
	}
	if _, err := service.Consume(ctx, "missing_user", codes[1]); !errors.Is(err, ErrInvalidRecoveryCode) {
		t.Fatalf("missing account recovery error = %v", err)
	}
}
