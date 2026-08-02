package httpapi

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestLegalRoutesServeEmbeddedPublicPages(t *testing.T) {
	t.Parallel()

	router := NewRouter()
	tests := []struct {
		name      string
		path      string
		topics    []string
		forbidden []string
	}{
		{
			name: "privacy",
			path: "/v1/legal/privacy",
			topics: []string{
				"隐私政策", "2026-07-19", "Clovery 服务运营者", "睿恩 梁", "support@clovery.cn",
				"CloveryID", "密码哈希", "Apple", "Google", "Huawei", "稳定标识",
				"日记", "照片", "跨设备", "Vault", "StoreKit", "交易", "权益",
				"日志", "安全", "保留", "账户删除", "未成年人", "政策更新",
				"30 日", "90 日", "180 日",
			},
			forbidden: []string{"端到端加密"},
		},
		{
			name: "terms",
			path: "/v1/legal/terms",
			topics: []string{
				"服务条款", "2026-07-19", "Clovery 服务运营者", "睿恩 梁", "support@clovery.cn",
				"账户责任", "用户内容", "第三方登录", "Apple", "Google", "Huawei",
				"订阅", "非消耗型权益", "同步", "备份", "删除", "禁止行为",
				"服务变更", "未成年人", "日记", "照片", "跨设备", "Vault",
				"StoreKit", "交易", "权益", "日志", "安全", "保留", "更新",
			},
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()

			request := httptest.NewRequest(http.MethodGet, test.path, nil)
			response := httptest.NewRecorder()

			router.ServeHTTP(response, request)

			if response.Code != http.StatusOK {
				t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
			}
			assertLegalResponseHeaders(t, response.Header())
			body := response.Body.String()
			for _, topic := range test.topics {
				if !strings.Contains(body, topic) {
					t.Errorf("body is missing topic %q", topic)
				}
			}
			for _, forbidden := range append(test.forbidden,
				"TODO", "example.com", "待定", "待补", "占位", "尚未公布", "某某公司", "示例公司",
				"<script", "<iframe", "http://", "https://",
			) {
				if strings.Contains(body, forbidden) {
					t.Errorf("body contains forbidden content %q", forbidden)
				}
			}
			for _, accessibilityMarker := range []string{
				`<html lang="zh-CN">`,
				`<meta name="viewport" content="width=device-width, initial-scale=1">`,
				"<main>",
				"<h1>",
			} {
				if !strings.Contains(body, accessibilityMarker) {
					t.Errorf("body is missing accessibility marker %q", accessibilityMarker)
				}
			}
		})
	}
}

func assertLegalResponseHeaders(t *testing.T, header http.Header) {
	t.Helper()

	for name, expected := range map[string]string{
		"Content-Type":            "text/html; charset=utf-8",
		"Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
		"X-Content-Type-Options":  "nosniff",
		"Referrer-Policy":         "no-referrer",
		"Cache-Control":           "public, max-age=300",
	} {
		if actual := header.Get(name); actual != expected {
			t.Errorf("%s = %q, want %q", name, actual, expected)
		}
	}
}
