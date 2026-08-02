package migration

import (
	"regexp"
	"strconv"
	"strings"

	"github.com/google/uuid"
)

var migrationSourceEntryIDPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$`)

var migrationEntryNamespace = uuid.MustParse("b456bbb9-1e9a-5d4b-87d2-47c23fd58e5f")
var migrationConflictNamespace = uuid.MustParse("d3f8a8ec-4721-5b02-9330-82026a6ed0fd")

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

func conflictEntryID(vaultID string, sourceEntryID string, contentSHA256 string, counter int) uuid.UUID {
	identity := vaultID + "\x00" + sourceEntryID + "\x00" + contentSHA256
	if counter > 0 {
		identity += "\x00" + strconv.Itoa(counter)
	}
	return uuid.NewSHA1(migrationConflictNamespace, []byte(identity))
}
