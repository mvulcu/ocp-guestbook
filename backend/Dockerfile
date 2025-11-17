# Stage 1: build
FROM registry.access.redhat.com/ubi10/go-toolset:10.0 AS builder

WORKDIR /workspace


COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o guestbook-api .

# Stage 2
FROM registry.access.redhat.com/ubi10-minimal:10.0

WORKDIR /opt/app

COPY --from=builder /workspace/guestbook-api /opt/app/guestbook-api

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s \
    CMD curl -f http://localhost:8080/health || exit 1

USER 1001

ENTRYPOINT ["/opt/app/guestbook-api"]
