# Clovery V2

Clovery V2 is the production-oriented cross-platform rewrite. The existing
`Clovery/` and `CloveryWidget/` directories remain the V1 migration source until
the migration window closes.

## Repository Layout

| Path | Responsibility |
| --- | --- |
| `apps/mobile` | Flutter UI, Drift local database, and sync engine |
| `services/api` | Clovery Go API and migration jobs |
| `contracts/openapi` | Single source of truth for the HTTP contract |
| `infra` | Local dependencies and deployment configuration |

OpenAPI is a versioned interface description stored in this repository. It is
not an OpenAI service and does not transmit user data.
