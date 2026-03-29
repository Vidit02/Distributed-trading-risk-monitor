# Build stage
FROM golang:1.25-alpine AS builder

WORKDIR /build

COPY shared/ ./shared/
COPY services/analytics/ ./services/analytics/

WORKDIR /build/services/analytics
RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -o /app/service .

# Runtime stage
FROM alpine:3.21
RUN apk --no-cache add ca-certificates tzdata
COPY --from=builder /app/service /service
ENTRYPOINT ["/service"]
