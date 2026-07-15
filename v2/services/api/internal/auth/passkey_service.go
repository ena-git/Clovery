package auth

import (
	"crypto/rand"
	"fmt"
	"io"
	"time"
)

const passkeyChallengeLifetime = 5 * time.Minute

type PasskeyService struct {
	sessions RecentSessionAuthenticator
	store    PasskeyStore
	engine   PasskeyEngine
	now      func() time.Time
	random   io.Reader
}

func NewPasskeyService(
	sessions RecentSessionAuthenticator,
	store PasskeyStore,
	engine PasskeyEngine,
) (*PasskeyService, error) {
	if sessions == nil || store == nil || engine == nil {
		return nil, fmt.Errorf("passkey dependencies are required")
	}
	return &PasskeyService{
		sessions: sessions,
		store:    store,
		engine:   engine,
		now:      func() time.Time { return time.Now().UTC() },
		random:   rand.Reader,
	}, nil
}
