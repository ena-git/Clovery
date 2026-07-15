package sync

import (
	"crypto/sha256"
	"encoding/json"
)

func OperationFingerprint(operation Operation) ([]byte, error) {
	payload, err := canonicalJSON(operation.Payload)
	if err != nil {
		return nil, ErrInvalidOperation
	}
	if operation.Deleted {
		payload = json.RawMessage(`{}`)
	}
	encoded, err := json.Marshal(struct {
		EntryID      string          `json:"entry_id"`
		BaseRevision int64           `json:"base_revision"`
		Payload      json.RawMessage `json:"payload"`
		Deleted      bool            `json:"deleted"`
	}{operation.EntryID, operation.BaseRevision, payload, operation.Deleted})
	if err != nil {
		return nil, err
	}
	hash := sha256.Sum256(encoded)
	return hash[:], nil
}

func canonicalJSON(payload json.RawMessage) (json.RawMessage, error) {
	var value any
	if len(payload) == 0 || json.Unmarshal(payload, &value) != nil {
		return nil, ErrInvalidOperation
	}
	encoded, err := json.Marshal(value)
	if err != nil {
		return nil, err
	}
	return encoded, nil
}
