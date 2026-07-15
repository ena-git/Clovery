package billing

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"

	"github.com/google/uuid"
)

func (verifier *AppleVerifier) AssignAccountToken(
	ctx context.Context,
	originalTransactionID string,
	transactionID string,
	accountID string,
	environment Environment,
) (VerifiedTransaction, error) {
	accountUUID, err := uuid.Parse(accountID)
	originalTransactionID = strings.TrimSpace(originalTransactionID)
	transactionID = strings.TrimSpace(transactionID)
	if err != nil || !environment.Valid() || originalTransactionID == "" || transactionID == "" ||
		len(originalTransactionID) > 128 || len(transactionID) > 128 ||
		(environment == EnvironmentSandbox && !verifier.allowSandbox) {
		return VerifiedTransaction{}, ErrVerificationFailed
	}
	contents, err := json.Marshal(map[string]string{"appAccountToken": accountUUID.String()})
	if err != nil {
		return VerifiedTransaction{}, ErrVerificationUnavailable
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
		ctx, http.MethodPut,
		baseURL+"/inApps/v1/transactions/"+url.PathEscape(originalTransactionID)+"/appAccountToken",
		bytes.NewReader(contents),
	)
	if err != nil {
		return VerifiedTransaction{}, ErrVerificationUnavailable
	}
	request.Header.Set("Authorization", "Bearer "+token)
	request.Header.Set("Accept", "application/json")
	request.Header.Set("Content-Type", "application/json")
	response, err := verifier.httpClient.Do(request)
	if err != nil {
		return VerifiedTransaction{}, ErrVerificationUnavailable
	}
	defer response.Body.Close()
	if response.StatusCode == http.StatusUnauthorized || response.StatusCode == http.StatusForbidden ||
		response.StatusCode == http.StatusTooManyRequests || response.StatusCode >= 500 {
		return VerifiedTransaction{}, ErrVerificationUnavailable
	}
	if response.StatusCode != http.StatusOK {
		return VerifiedTransaction{}, ErrVerificationFailed
	}
	verified, err := verifier.Verify(ctx, transactionID, environment)
	if err != nil {
		return VerifiedTransaction{}, err
	}
	if verified.OriginalTransactionID != originalTransactionID ||
		verified.AppAccountToken != accountUUID.String() {
		return VerifiedTransaction{}, ErrVerificationFailed
	}
	return verified, nil
}
