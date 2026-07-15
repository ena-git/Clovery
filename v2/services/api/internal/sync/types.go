package sync

import (
	"encoding/json"
	"time"
)

const (
	StatusApplied  = "applied"
	StatusConflict = "conflict"
)

type Operation struct {
	OperationID  string          `json:"operation_id"`
	EntryID      string          `json:"entry_id"`
	BaseRevision int64           `json:"base_revision"`
	Payload      json.RawMessage `json:"payload"`
	Deleted      bool            `json:"deleted"`
}

type Entry struct {
	ID        string          `json:"entry_id"`
	Revision  int64           `json:"revision"`
	Payload   json.RawMessage `json:"payload"`
	DeletedAt *time.Time      `json:"deleted_at,omitempty"`
}

type Decision struct {
	OperationID    string `json:"operation_id"`
	Status         string `json:"status"`
	Entry          *Entry `json:"entry,omitempty"`
	ServerSnapshot *Entry `json:"server_snapshot,omitempty"`
	Cursor         int64  `json:"cursor,omitempty"`
}

type Change struct {
	Cursor      int64           `json:"cursor"`
	EntityType  string          `json:"entity_type"`
	EntityID    string          `json:"entity_id"`
	Revision    int64           `json:"revision"`
	OperationID string          `json:"operation_id"`
	Payload     json.RawMessage `json:"payload"`
	Deleted     bool            `json:"deleted"`
	ChangedAt   time.Time       `json:"changed_at"`
}

type PullPage struct {
	Changes    []Change `json:"changes"`
	NextCursor int64    `json:"next_cursor"`
	HasMore    bool     `json:"has_more"`
}
