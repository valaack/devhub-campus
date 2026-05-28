# ---- Stage 1 : build du binaire Go ----
FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/notif ./cmd

# ---- Stage 2 : runtime minimal ----
FROM gcr.io/distroless/static:nonroot AS runtime
LABEL org.opencontainers.image.source="https://github.com/valaack/devhub-campus"
COPY --from=build /out/notif /notif
ENV PORT=8080 \
    LOG_LEVEL=info
EXPOSE 8080
ENTRYPOINT ["/notif"]
