FROM golang:1.26.5-alpine AS build

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/clovery-api ./cmd/api
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/clovery-migrate ./cmd/migrate

FROM alpine:3.23

RUN apk add --no-cache ca-certificates \
    && addgroup -S clovery \
    && adduser -S clovery -G clovery

WORKDIR /app
COPY --from=build /out/clovery-api /app/clovery-api
COPY --from=build /out/clovery-migrate /app/clovery-migrate
COPY migrations /app/migrations

ENV MIGRATIONS_PATH=/app/migrations
EXPOSE 8080
USER clovery
ENTRYPOINT ["/app/clovery-api"]
