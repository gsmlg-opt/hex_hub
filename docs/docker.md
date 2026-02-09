# Docker Deployment Guide

This guide covers how to use Docker to deploy HexHub.

## Quick Start

### Using Docker Compose

```bash
# Build and start the service
docker-compose up -d

# View logs
docker-compose logs -f hex_hub

# Stop services
docker-compose down
```

### Using Docker directly

```bash
# Build the image
docker build -t hex_hub:latest .

# Run the container
docker run -p 4000:4000 \
  -e SECRET_KEY_BASE=your-secret-key \
  -e PHX_HOST=localhost \
  -v $(pwd)/storage:/app/priv/storage \
  hex_hub:latest
```

## Environment Variables

### Required
- `SECRET_KEY_BASE`: 64-byte secret key for Phoenix
- `PHX_HOST`: Hostname for Phoenix (e.g., localhost, your-domain.com)

### Optional
- `MIX_ENV`: Set to `prod` for production (default: prod)
- `CLUSTERING_ENABLED`: Enable clustering (default: false)
- `STORAGE_TYPE`: `local` or `s3` (default: local)
- `S3_BUCKET`: S3 bucket name (if using S3)
- `AWS_ACCESS_KEY_ID`: AWS access key (if using S3)
- `AWS_SECRET_ACCESS_KEY`: AWS secret key (if using S3)
- `AWS_REGION`: AWS region (if using S3)
- `AWS_S3_HOST`: Custom S3 host (for S3-compatible services)
- `AWS_S3_PORT`: Custom S3 port (default: 443)
- `AWS_S3_PATH_STYLE`: Use path-style addressing (for MinIO, default: false)
- `AWS_S3_SCHEME`: URL scheme `http` or `https` (default: https)
- `MNESIA_DIR`: Directory for Mnesia data (default: /app/priv/storage/mnesia)
- `PORT`: Port to run on (default: 4000)

## Docker Compose Examples

### Basic Single Node

```yaml
version: '3.8'
services:
  hex_hub:
    image: ghcr.io/gsmlg-dev/hex_hub:latest
    ports:
      - "4000:4000"
    environment:
      - SECRET_KEY_BASE=your-secret-key
      - PHX_HOST=your-domain.com
    volumes:
      - ./storage:/app/priv/storage
```

### Clustered Deployment

```yaml
version: '3.8'
services:
  hex_hub1:
    image: ghcr.io/gsmlg-dev/hex_hub:latest
    ports:
      - "4000:4000"
    environment:
      - SECRET_KEY_BASE=your-secret-key
      - PHX_HOST=your-domain.com
      - CLUSTERING_ENABLED=true
      - NODE_NAME=hex_hub1@hex_hub1
    volumes:
      - hex_hub_storage:/app/priv/storage

  hex_hub2:
    image: ghcr.io/gsmlg-dev/hex_hub:latest
    ports:
      - "4001:4000"
    environment:
      - SECRET_KEY_BASE=your-secret-key
      - PHX_HOST=your-domain.com
      - CLUSTERING_ENABLED=true
      - NODE_NAME=hex_hub2@hex_hub2
    volumes:
      - hex_hub_storage:/app/priv/storage
    depends_on:
      - hex_hub1
```

## Health Checks

The Docker image includes health checks that monitor:
- Database connectivity
- Application responsiveness
- Storage accessibility

Health check endpoint: `http://localhost:4000/health`

## Storage

### Local Storage

Mount a volume for persistent storage:

```bash
docker run -v /host/path/storage:/app/priv/storage hex_hub:latest
```

### S3 Storage

Configure S3 storage with environment variables:

```bash
docker run \
  -e STORAGE_TYPE=s3 \
  -e S3_BUCKET=your-bucket \
  -e AWS_ACCESS_KEY_ID=your-key \
  -e AWS_SECRET_ACCESS_KEY=your-secret \
  -e AWS_REGION=us-east-1 \
  hex_hub:latest
```

For S3-compatible services (MinIO, DigitalOcean Spaces, etc.):

```bash
docker run \
  -e STORAGE_TYPE=s3 \
  -e S3_BUCKET=your-bucket \
  -e AWS_ACCESS_KEY_ID=your-key \
  -e AWS_SECRET_ACCESS_KEY=your-secret \
  -e AWS_REGION=us-east-1 \
  -e AWS_S3_HOST=minio-server.com \
  -e AWS_S3_PORT=9000 \
  -e AWS_S3_PATH_STYLE=true \
  -e AWS_S3_SCHEME=http \
  hex_hub:latest
```

## Production Deployment

### Using Kubernetes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hex-hub
spec:
  replicas: 2
  selector:
    matchLabels:
      app: hex-hub
  template:
    metadata:
      labels:
        app: hex-hub
    spec:
      containers:
      - name: hex-hub
        image: ghcr.io/gsmlg-dev/hex_hub:latest
        ports:
        - containerPort: 4000
        env:
        - name: SECRET_KEY_BASE
          valueFrom:
            secretKeyRef:
              name: hex-hub-secrets
              key: secret-key-base
        - name: PHX_HOST
          value: "your-domain.com"
        volumeMounts:
        - name: storage
          mountPath: /app/priv/storage
      volumes:
      - name: storage
        persistentVolumeClaim:
          claimName: hex-hub-storage
```

### Using Docker Swarm

```bash
# Initialize swarm
docker swarm init

# Deploy stack
docker stack deploy -c docker-compose.yml hex_hub

# Check status
docker service ls
```

## Monitoring

### Logs

```bash
# View container logs
docker logs hex_hub

# Follow logs in real-time
docker logs -f hex_hub

# View specific log file inside container
docker exec hex_hub tail -f /app/log/prod.log
```

### Metrics

HexHub exposes Prometheus metrics at `/metrics` endpoint when running in production.

## Troubleshooting

### Common Issues

1. **Database Connection**: Ensure Mnesia directory is writable
2. **Storage Permissions**: Check volume mount permissions
3. **Memory Issues**: Increase container memory limits
4. **Network Issues**: Ensure proper port mapping

### Debug Mode

Run with debug logging:

```bash
docker run -e LOG_LEVEL=debug hex_hub:latest
```

### Interactive Shell

```bash
# Get shell access
docker exec -it hex_hub sh

# Or run with shell
docker run -it hex_hub:latest sh
```

## Building Custom Images

### Multi-stage Build

The Dockerfile uses multi-stage builds to minimize final image size:

- **Builder stage**: Contains build tools and dependencies
- **Final stage**: Minimal runtime image with only necessary components

### Build Arguments

Customize the build with arguments:

```bash
docker build \
  --build-arg ELIXIR_VERSION=1.16.0 \
  --build-arg OTP_VERSION=26.2 \
  --build-arg DEBIAN_VERSION=bookworm-20240130-slim \
  -t hex_hub:custom .
```

## Security Considerations

- The container runs as non-root user (`nobody`)
- Secrets should be passed via environment variables or Docker secrets
- Use specific image tags instead of `latest` in production
- Regularly update base images and dependencies

## GitHub Actions

The repository includes a GitHub Actions workflow that:
- Runs tests on every PR
- Builds and pushes images to GitHub Container Registry
- Creates releases with Docker images
- Supports multi-architecture builds (amd64, arm64)

Images are available at: `ghcr.io/${{ github.repository }}:latest`