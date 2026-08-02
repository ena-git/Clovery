package legal

import (
	"bytes"
	_ "embed"
)

//go:embed privacy.zh-CN.html
var privacyPage []byte

//go:embed terms.zh-CN.html
var termsPage []byte

func Privacy() []byte {
	return bytes.Clone(privacyPage)
}

func Terms() []byte {
	return bytes.Clone(termsPage)
}
