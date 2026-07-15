package observability

import (
	"fmt"
	"net/http"
)

func (registry *Registry) Handler() http.Handler {
	return http.HandlerFunc(func(responseWriter http.ResponseWriter, _ *http.Request) {
		responseWriter.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
		counters, gauges := registry.snapshot()
		for _, metric := range allowedCounters {
			_, _ = fmt.Fprintf(responseWriter, "# TYPE %s counter\n%s %d\n", metric, metric, counters[metric])
		}
		for _, metric := range allowedGauges {
			_, _ = fmt.Fprintf(responseWriter, "# TYPE %s gauge\n%s %d\n", metric, metric, gauges[metric])
		}
	})
}
