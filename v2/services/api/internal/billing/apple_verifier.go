package billing

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
)

const maximumAppleResponseSize = 1024 * 1024

func (verifier *AppleVerifier) Verify(
	ctx context.Context,
	transactionID string,
	environment Environment,
) (VerifiedTransaction, error) {
	if transactionID == "" || !environment.Valid() {
		return VerifiedTransaction{}, ErrVerificationFailed
	}
	if environment == EnvironmentSandbox && !verifier.allowSandbox {
		return VerifiedTransaction{}, ErrVerificationFailed
	}
	token, err := verifier.bearerToken()
	if err != nil {
		return VerifiedTransaction{}, fmt.Errorf("%w: %v", ErrVerificationUnavailable, err)
	}
	baseURL := verifier.productionBaseURL
	if environment == EnvironmentSandbox {
		baseURL = verifier.sandboxBaseURL
	}
	request, err := http.NewRequestWithContext(
		ctx, http.MethodGet,
		baseURL+"/inApps/v1/transactions/"+url.PathEscape(transactionID), nil,
	)
	if err != nil {
		return VerifiedTransaction{}, fmt.Errorf("%w: create request", ErrVerificationUnavailable)
	}
	request.Header.Set("Authorization", "Bearer "+token)
	request.Header.Set("Accept", "application/json")
	response, err := verifier.httpClient.Do(request)
	if err != nil {
		return VerifiedTransaction{}, fmt.Errorf("%w: request Apple transaction", ErrVerificationUnavailable)
	}
	defer response.Body.Close()
	if response.StatusCode == http.StatusUnauthorized || response.StatusCode == http.StatusTooManyRequests ||
		response.StatusCode >= 500 {
		return VerifiedTransaction{}, ErrVerificationUnavailable
	}
	if response.StatusCode != http.StatusOK {
		return VerifiedTransaction{}, ErrVerificationFailed
	}
	contents, err := io.ReadAll(io.LimitReader(response.Body, maximumAppleResponseSize+1))
	if err != nil || len(contents) > maximumAppleResponseSize {
		return VerifiedTransaction{}, ErrVerificationFailed
	}
	var payload struct {
		SignedTransactionInfo string `json:"signedTransactionInfo"`
	}
	if err := json.Unmarshal(contents, &payload); err != nil || payload.SignedTransactionInfo == "" {
		return VerifiedTransaction{}, ErrVerificationFailed
	}
	return verifier.verifySignedTransaction(payload.SignedTransactionInfo, transactionID, environment)
}
