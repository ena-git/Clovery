package main

import (
	"testing"

	"github.com/clovery/clovery/services/api/internal/database"
)

func TestParseDirectionAcceptsOnlyExplicitUp(t *testing.T) {
	testCases := []struct {
		name      string
		arguments []string
		want      database.Direction
		wantError bool
	}{
		{name: "up", arguments: []string{"up"}, want: database.Up},
		{name: "down", arguments: []string{"down"}, wantError: true},
		{name: "missing", arguments: nil, wantError: true},
		{name: "unknown", arguments: []string{"reset"}, wantError: true},
	}

	for _, testCase := range testCases {
		t.Run(testCase.name, func(t *testing.T) {
			direction, err := parseDirection(testCase.arguments)
			if testCase.wantError {
				if err == nil {
					t.Fatal("parseDirection() accepted invalid arguments")
				}
				return
			}
			if err != nil {
				t.Fatalf("parseDirection() returned an unexpected error: %v", err)
			}
			if direction != testCase.want {
				t.Fatalf("direction = %d, want %d", direction, testCase.want)
			}
		})
	}
}
