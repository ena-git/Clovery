package billing

type appleNotificationAppMetadata struct {
	BundleID    string `json:"bundleId"`
	AppAppleID  int64  `json:"appAppleId"`
	Environment string `json:"environment"`
}

func (claims appleNotificationClaims) notificationAppMetadata() (
	appleNotificationAppMetadata,
	bool,
	error,
) {
	data := appleNotificationAppMetadata{
		BundleID: claims.Data.BundleID, AppAppleID: claims.Data.AppAppleID,
		Environment: claims.Data.Environment,
	}
	candidates := make([]appleNotificationAppMetadata, 0, 3)
	if data.present() || claims.Data.Status != 0 || claims.Data.SignedRenewalInfo != "" ||
		claims.Data.SignedTransactionInfo != "" {
		candidates = append(candidates, data)
	}
	if claims.Summary.present() {
		candidates = append(candidates, claims.Summary)
	}
	if claims.AppData.present() {
		candidates = append(candidates, claims.AppData)
	}
	if len(candidates) > 1 {
		return appleNotificationAppMetadata{}, false, ErrVerificationFailed
	}
	if len(candidates) == 0 {
		return appleNotificationAppMetadata{}, false, nil
	}
	return candidates[0], true, nil
}

func (metadata appleNotificationAppMetadata) present() bool {
	return metadata.BundleID != "" || metadata.AppAppleID != 0 || metadata.Environment != ""
}

func (verifier *AppleVerifier) validateNotificationAppMetadata(
	metadata appleNotificationAppMetadata,
) (Environment, error) {
	if metadata.BundleID != verifier.bundleID {
		return "", ErrVerificationFailed
	}
	environment, ok := parseAppleEnvironment(metadata.Environment)
	if !ok || (environment == EnvironmentSandbox && !verifier.allowSandbox) {
		return "", ErrVerificationFailed
	}
	if metadata.AppAppleID != 0 && metadata.AppAppleID != verifier.appAppleID {
		return "", ErrVerificationFailed
	}
	if environment == EnvironmentProduction && metadata.AppAppleID != verifier.appAppleID {
		return "", ErrVerificationFailed
	}
	return environment, nil
}
