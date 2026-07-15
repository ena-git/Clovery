package sync

import (
	"encoding/json"
	"errors"
	"time"
)

var ErrInvalidOperation = errors.New("invalid sync operation")

func DecideOperation(current *Entry, operation Operation, now time.Time) (Decision, error) {
	if operation.OperationID == "" || operation.EntryID == "" || operation.BaseRevision < 0 {
		return Decision{}, ErrInvalidOperation
	}
	operationPayload, err := canonicalJSON(operation.Payload)
	if err != nil {
		return Decision{}, ErrInvalidOperation
	}
	if current == nil && operation.BaseRevision != 0 {
		return Decision{OperationID: operation.OperationID, Status: StatusConflict}, nil
	}
	if current != nil && current.Revision != operation.BaseRevision {
		snapshot := cloneEntry(*current)
		return Decision{
			OperationID:    operation.OperationID,
			Status:         StatusConflict,
			ServerSnapshot: &snapshot,
		}, nil
	}

	next := Entry{
		ID: operation.EntryID, Revision: operation.BaseRevision + 1,
		Payload: operationPayload,
	}
	if current != nil {
		next.Payload = append(json.RawMessage(nil), current.Payload...)
	}
	if operation.Deleted {
		deletedAt := now.UTC()
		next.DeletedAt = &deletedAt
	} else {
		next.Payload = operationPayload
	}
	return Decision{OperationID: operation.OperationID, Status: StatusApplied, Entry: &next}, nil
}

func cloneEntry(entry Entry) Entry {
	entry.Payload = append(json.RawMessage(nil), entry.Payload...)
	if entry.DeletedAt != nil {
		deletedAt := *entry.DeletedAt
		entry.DeletedAt = &deletedAt
	}
	return entry
}
