# Build stage
FROM golang:1.25-alpine AS builder

WORKDIR /build

# Copy shared module (needed by replace directive in go.mod)
COPY shared/ ./shared/

# Copy service source
COPY services/transaction/ ./services/transaction/

WORKDIR /build/services/transaction
RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -o /app/service .

# Runtime stage
FROM alpine:3.21
RUN apk --no-cache add ca-certificates tzdata
COPY --from=builder /app/service /service
EXPOSE 8080
ENTRYPOINT ["/service"]
