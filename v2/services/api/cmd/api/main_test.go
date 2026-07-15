package main

import (
	"net/http"
	"testing"

	"github.com/clovery/clovery/services/api/internal/config"
)

func TestNewServerUsesConfiguredPortAndHandler(t *testing.T) {
	handler := http.NewServeMux()
	server := newServer(config.Config{Port: "9090"}, handler)

	if server.Addr != ":9090" {
		t.Fatalf("Addr = %q", server.Addr)
	}
	if server.Handler != handler {
		t.Fatal("Handler was not preserved")
	}
}
