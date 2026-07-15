package account

import (
	"regexp"
	"strings"
)

var loginIDPattern = regexp.MustCompile(`^[a-z][a-z0-9_]{3,23}$`)

var reservedLoginIDs = map[string]struct{}{
	"admin":         {},
	"administrator": {},
	"api":           {},
	"clovery":       {},
	"help":          {},
	"root":          {},
	"security":      {},
	"support":       {},
	"system":        {},
}

func NormalizeLoginID(candidate string) (string, error) {
	normalizedID := strings.ToLower(strings.TrimSpace(candidate))
	if !loginIDPattern.MatchString(normalizedID) {
		return "", ErrInvalidLoginID
	}
	if _, reserved := reservedLoginIDs[normalizedID]; reserved {
		return "", ErrInvalidLoginID
	}
	return normalizedID, nil
}
