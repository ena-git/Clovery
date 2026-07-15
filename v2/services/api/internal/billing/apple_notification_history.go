package billing

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/url"
	"strings"
)

const maximumAppleHistoryResponseSize = 24 * 1024 * 1024

func (verifier *AppleVerifier) FetchNotificationHistoryPage(
	ctx context.Context,
	query NotificationHistoryQuery,
) (NotificationHistoryPage, error) {
	if query.StartAt.IsZero() || query.EndAt.IsZero() || !query.StartAt.Before(query.EndAt) ||
		!query.Environment.Valid() || len(query.PaginationToken) > 4096 ||
		(query.Environment == EnvironmentSandbox && !verifier.allowSandbox) {
		return NotificationHistoryPage{}, ErrInvalidRequest
	}
	contents, err := json.Marshal(struct {
		StartDate    int64 `json:"startDate"`
		EndDate      int64 `json:"endDate"`
		OnlyFailures bool  `json:"onlyFailures"`
	}{
		StartDate: query.StartAt.UnixMilli(), EndDate: query.EndAt.UnixMilli(),
		OnlyFailures: query.OnlyFailures,
	})
	if err != nil {
		return NotificationHistoryPage{}, ErrVerificationUnavailable
	}
	token, err := verifier.bearerToken()
	if err != nil {
		return NotificationHistoryPage{}, ErrVerificationUnavailable
	}
	baseURL := verifier.productionBaseURL
	if query.Environment == EnvironmentSandbox {
		baseURL = verifier.sandboxBaseURL
	}
	endpoint, err := url.Parse(baseURL + "/inApps/v1/notifications/history")
	if err != nil {
		return NotificationHistoryPage{}, ErrVerificationUnavailable
	}
	if query.PaginationToken != "" {
		parameters := endpoint.Query()
		parameters.Set("paginationToken", query.PaginationToken)
		endpoint.RawQuery = parameters.Encode()
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint.String(), bytes.NewReader(contents))
	if err != nil {
		return NotificationHistoryPage{}, ErrVerificationUnavailable
	}
	request.Header.Set("Authorization", "Bearer "+token)
	request.Header.Set("Accept", "application/json")
	request.Header.Set("Content-Type", "application/json")
	response, err := verifier.httpClient.Do(request)
	if err != nil {
		return NotificationHistoryPage{}, ErrVerificationUnavailable
	}
	defer response.Body.Close()
	if response.StatusCode == http.StatusUnauthorized || response.StatusCode == http.StatusForbidden ||
		response.StatusCode == http.StatusTooManyRequests || response.StatusCode >= 500 {
		return NotificationHistoryPage{}, ErrVerificationUnavailable
	}
	if response.StatusCode != http.StatusOK {
		return NotificationHistoryPage{}, ErrVerificationFailed
	}
	responseContents, err := io.ReadAll(io.LimitReader(response.Body, maximumAppleHistoryResponseSize+1))
	if err != nil || len(responseContents) > maximumAppleHistoryResponseSize {
		return NotificationHistoryPage{}, ErrVerificationFailed
	}
	var payload struct {
		NotificationHistory []struct {
			SignedPayload string `json:"signedPayload"`
		} `json:"notificationHistory"`
		HasMore         bool   `json:"hasMore"`
		PaginationToken string `json:"paginationToken"`
	}
	if json.Unmarshal(responseContents, &payload) != nil ||
		(payload.HasMore && strings.TrimSpace(payload.PaginationToken) == "") {
		return NotificationHistoryPage{}, ErrVerificationFailed
	}
	signedPayloads := make([]string, 0, len(payload.NotificationHistory))
	for _, historyItem := range payload.NotificationHistory {
		signedPayload := strings.TrimSpace(historyItem.SignedPayload)
		if signedPayload == "" || len(signedPayload) > maximumAppleNotificationSize {
			return NotificationHistoryPage{}, ErrVerificationFailed
		}
		signedPayloads = append(signedPayloads, signedPayload)
	}
	return NotificationHistoryPage{
		SignedPayloads: signedPayloads, HasMore: payload.HasMore,
		PaginationToken: strings.TrimSpace(payload.PaginationToken),
	}, nil
}
