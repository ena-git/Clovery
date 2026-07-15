package migration

import (
	"regexp"
	"strings"

	"github.com/google/uuid"
)

var migrationSourceEntryIDPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$`)

var migrationEntryNamespace = uuid.MustParse("b456bbb9-1e9a-5d4b-87d2-47c23fd58e5f")

func normalizeEntryIdentity(vaultID string, sourceEntryID string) (string, string, error) {
	if strings.TrimSpace(sourceEntryID) != sourceEntryID ||
		!migrationSourceEntryIDPattern.MatchString(sourceEntryID) {
		return "", "", ErrInvalidBundle
	}
	if parsed, err := uuid.Parse(sourceEntryID); err == nil {
		return sourceEntryID, parsed.String(), nil
	}
	internalID := uuid.NewSHA1(
		migrationEntryNamespace,
		[]byte(vaultID+"\x00"+sourceEntryID),
	)
	return sourceEntryID, internalID.String(), nil
}
