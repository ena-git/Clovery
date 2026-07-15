package observability

import "sync"

type Registry struct {
	mutex    sync.RWMutex
	counters map[Counter]uint64
	gauges   map[Gauge]int64
}

func NewRegistry() *Registry {
	return &Registry{
		counters: make(map[Counter]uint64),
		gauges:   make(map[Gauge]int64),
	}
}

func (registry *Registry) Increment(metric Counter) {
	registry.Add(metric, 1)
}

func (registry *Registry) Add(metric Counter, delta uint64) {
	if registry == nil || !validCounter(metric) {
		return
	}
	registry.mutex.Lock()
	defer registry.mutex.Unlock()
	registry.counters[metric] += delta
}

func (registry *Registry) Set(metric Gauge, value int64) {
	if registry == nil || !validGauge(metric) {
		return
	}
	registry.mutex.Lock()
	defer registry.mutex.Unlock()
	registry.gauges[metric] = value
}

func (registry *Registry) Adjust(metric Gauge, delta int64) {
	if registry == nil || !validGauge(metric) {
		return
	}
	registry.mutex.Lock()
	defer registry.mutex.Unlock()
	registry.gauges[metric] += delta
	if registry.gauges[metric] < 0 {
		registry.gauges[metric] = 0
	}
}

func (registry *Registry) snapshot() (map[Counter]uint64, map[Gauge]int64) {
	registry.mutex.RLock()
	defer registry.mutex.RUnlock()
	counters := make(map[Counter]uint64, len(registry.counters))
	for metric, value := range registry.counters {
		counters[metric] = value
	}
	gauges := make(map[Gauge]int64, len(registry.gauges))
	for metric, value := range registry.gauges {
		gauges[metric] = value
	}
	return counters, gauges
}
