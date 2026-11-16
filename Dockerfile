# Stage 1: Build Go binaries (toolchain pinned to the version in go.mod)
FROM golang:1.25.1-alpine AS builder

RUN apk add --no-cache git ca-certificates tzdata

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
# server: API · migrate: versioned schema migrations (schema-owner role)
# auditverify: read-only audit chain check · rekey: PII key rotation
RUN for c in api migrate auditverify rekey; do \
      CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o /app/bin/$c ./cmd/$c || exit 1; \
    done && mv /app/bin/api /app/bin/server

# Stage 2: Minimal runtime, non-root (audit DMB-019)
FROM alpine:3.20

RUN apk add --no-cache ca-certificates tzdata \
    && addgroup -S app && adduser -S -G app -H -s /sbin/nologin app
ENV TZ=Asia/Jakarta

WORKDIR /app

COPY --from=builder /app/bin/ /app/
COPY --from=builder /app/web /app/web
RUN mkdir -p /app/web/admin/uploads && chown -R app:app /app/web/admin/uploads

USER app

EXPOSE 8080

CMD ["/app/server"]
