package config

import (
	"fmt"
	"net/url"
	"strconv"
	"strings"
)

func loadS3AllowInsecure(endpoint string, rawValue string) (bool, error) {
	allowInsecure := false
	if strings.TrimSpace(rawValue) != "" {
		parsed, err := strconv.ParseBool(strings.TrimSpace(rawValue))
		if err != nil {
			return false, fmt.Errorf("S3_ALLOW_INSECURE must be true or false")
		}
		allowInsecure = parsed
	}
	parsedEndpoint, err := url.Parse(strings.TrimSpace(endpoint))
	if err == nil && parsedEndpoint.Scheme == "http" && !allowInsecure {
		return false, fmt.Errorf("S3_ALLOW_INSECURE=true is required for an HTTP S3 endpoint")
	}
	return allowInsecure, nil
}
