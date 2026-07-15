package httpapi

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
)

func decodeJSON(responseWriter http.ResponseWriter, request *http.Request, destination any) error {
	return decodeJSONWithLimit(responseWriter, request, destination, 64*1024)
}

func decodeJSONWithLimit(
	responseWriter http.ResponseWriter,
	request *http.Request,
	destination any,
	maximumBytes int64,
) error {
	request.Body = http.MaxBytesReader(responseWriter, request.Body, maximumBytes)
	decoder := json.NewDecoder(request.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return fmt.Errorf("request body must contain one JSON value")
	}
	return nil
}

func writeAPIError(responseWriter http.ResponseWriter, status int, code string, message string) {
	writeJSON(responseWriter, status, map[string]string{"code": code, "message": message})
}

func writeJSON(responseWriter http.ResponseWriter, status int, value any) {
	responseWriter.Header().Set("Content-Type", "application/json")
	responseWriter.WriteHeader(status)
	_ = json.NewEncoder(responseWriter).Encode(value)
}
