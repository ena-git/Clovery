package config

import (
	"fmt"
	"strconv"
	"strings"
)

func parseRequiredBoolean(name string, value string) (bool, error) {
	parsed, err := strconv.ParseBool(strings.TrimSpace(value))
	if err != nil {
		return false, fmt.Errorf("%s must be true or false", name)
	}
	return parsed, nil
}
