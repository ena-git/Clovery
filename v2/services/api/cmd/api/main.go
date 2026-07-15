package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/clovery/clovery/services/api/internal/config"
)

func main() {
	applicationConfig, err := config.Load()
	if err != nil {
		slog.Error("load configuration", "error", err)
		os.Exit(1)
	}
	startupContext, cancelStartup := context.WithTimeout(context.Background(), 5*time.Second)
	databaseHandle, err := openApplicationDatabase(startupContext, applicationConfig.DatabaseURL)
	cancelStartup()
	if err != nil {
		slog.Error("connect application database", "error", err)
		os.Exit(1)
	}
	defer databaseHandle.Close()

	handler, err := buildHandler(databaseHandle, applicationConfig)
	if err != nil {
		slog.Error("build application handler", "error", err)
		os.Exit(1)
	}

	server := newServer(applicationConfig, handler)
	shutdownContext, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go func() {
		<-shutdownContext.Done()
		gracefulContext, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if shutdownErr := server.Shutdown(gracefulContext); shutdownErr != nil {
			slog.Error("shutdown HTTP server", "error", shutdownErr)
		}
	}()

	slog.Info("starting Clovery API", "address", server.Addr)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		slog.Error("serve HTTP", "error", err)
		os.Exit(1)
	}
}

func newServer(applicationConfig config.Config, handler http.Handler) *http.Server {
	return &http.Server{
		Addr:              ":" + applicationConfig.Port,
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
}
