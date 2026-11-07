# Stage 1: Build Go Binary
FROM golang:alpine AS builder

RUN apk add --no-cache git ca-certificates tzdata

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o /app/server ./cmd/api

# Stage 2: Minimal Production Runtime
FROM alpine:3.20

RUN apk add --no-cache ca-certificates tzdata
ENV TZ=Asia/Jakarta

WORKDIR /app

COPY --from=builder /app/server /app/server
COPY --from=builder /app/web /app/web

EXPOSE 8080

CMD ["/app/server"]
