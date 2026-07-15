package config

import (
	"fmt"
	"strings"
)

type DeploymentEnvironment string

const (
	DeploymentDevelopment DeploymentEnvironment = "development"
	DeploymentStaging     DeploymentEnvironment = "staging"
	DeploymentProduction  DeploymentEnvironment = "production"
)

func parseDeploymentEnvironment(value string) (DeploymentEnvironment, error) {
	environment := DeploymentEnvironment(strings.ToLower(strings.TrimSpace(value)))
	switch environment {
	case DeploymentDevelopment, DeploymentStaging, DeploymentProduction:
		return environment, nil
	default:
		return "", fmt.Errorf("DEPLOYMENT_ENVIRONMENT must be development, staging, or production")
	}
}
