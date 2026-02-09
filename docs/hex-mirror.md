# HEX_MIRROR Guide for HexHub

This guide explains how to use HexHub as a Hex package mirror with Mix using the `HEX_MIRROR` environment variable.

## Overview

HexHub can now be used as a drop-in replacement for hex.pm when running `mix deps.get`. This is achieved by setting the `HEX_MIRROR` environment variable to point to your HexHub instance.

## Key Features

✅ **Complete Mix Compatibility**: All required endpoints for Mix dependency resolution
✅ **Dual URL Support**: Both root-level and `/api` prefixed endpoints
✅ **Upstream Fallback**: Automatically fetches packages from hex.pm when not available locally
✅ **Transparent Caching**: Once fetched, packages are cached locally for faster access
✅ **Authentication Support**: Works with private packages requiring API keys

## Setup

### 1. Start HexHub

```bash
# Start the HexHub server
mix phx.server

# Or with clustering
PORT=4000 NODE_NAME=hex_hub1 ./scripts/cluster.sh start
```

### 2. Configure HEX_MIRROR

```bash
# Set HEX_MIRROR to point to your HexHub instance
export HEX_MIRROR=http://localhost:4000

# Or for production
export HEX_MIRROR=https://hexhub.your-domain.com
```

### 3. Use with Mix

```bash
# Mix will now fetch packages from HexHub instead of hex.pm
mix deps.get

# Your project dependencies will be resolved and downloaded through HexHub
```

## Supported Endpoints

### Package Metadata
- `GET /packages` - List packages
- `GET /packages/:name` - Get package details
- `GET /packages/:name/releases/:version` - Get release info

### Package Downloads
- `GET /packages/:name/releases/:version/download` - Download package tarball
- `GET /tarballs/:package-version.tar` - Mix-compatible tarball endpoint
- `GET /packages/:name/releases/:version/docs/download` - Download documentation

### Dependency Resolution
- `GET /installs/:elixir_version/:requirements` - Mix dependency resolution

### Repository Info
- `GET /repos` - List repositories
- `GET /repos/:name` - Get repository details

## URL Patterns

HexHub supports both URL patterns for maximum compatibility:

### Root-Level URLs (for HEX_MIRROR)
```
http://localhost:4000/packages
http://localhost:4000/tarballs/phoenix-1.7.0.tar
http://localhost:4000/installs/1.15/eyJwaG9lbml4IjogIj49IDEuMC4wIn0=
```

### API Prefixed URLs (for direct API access)
```
http://localhost:4000/api/packages
http://localhost:4000/api/tarballs/phoenix-1.7.0.tar
http://localhost:4000/api/installs/1.15/eyJwaG9lbml4IjogIj49IDEuMC4wIn0=
```

## Configuration Options

### Upstream Configuration

HexHub can automatically fetch packages from an upstream hex repository when they're not available locally:

```elixir
# config/config.exs
config :hex_hub, :upstream,
  enabled: true,
  api_url: "https://hex.pm",
  repo_url: "https://repo.hex.pm",
  timeout: 30_000,
  retry_attempts: 3,
  retry_delay: 1_000
```

Environment variables:
- `UPSTREAM_ENABLED` - Enable/disable upstream fetching (default: true)
- `UPSTREAM_URL` - Upstream repository URL (default: https://hex.pm)
- `UPSTREAM_TIMEOUT` - Request timeout in milliseconds (default: 30000)

### Storage Configuration

Choose between local filesystem storage or S3-compatible storage:

```elixir
# Local storage (default)
config :hex_hub, storage_type: :local

# S3 storage
config :hex_hub, storage_type: :s3
```

## Testing

Run the included test script to verify HEX_MIRROR functionality:

```bash
# Test against localhost
./test_hex_mirror.sh

# Test against remote instance
HEX_HUB_URL=https://hexhub.your-domain.com ./test_hex_mirror.sh

# Test with specific package
TEST_PACKAGE=phoenix ./test_hex_mirror.sh
```

## Troubleshooting

### Common Issues

1. **Connection refused**
   - Ensure HexHub is running: `mix phx.server`
   - Check the port: Default is 4000

2. **404 Not Found errors**
   - Verify HEX_MIRROR URL is correct
   - Check if the package exists locally or upstream is enabled

3. **Authentication errors**
   - For private packages, ensure API keys are configured
   - Check repository access permissions

4. **Slow downloads**
   - Enable upstream fetching for automatic caching
   - Consider using S3 storage for better performance

### Debug Mode

Enable debug logging to troubleshoot issues:

```elixir
# config/dev.exs
config :logger, level: :debug
```

### Monitoring

Check HexHub logs for Mix requests:

```bash
# Monitor Mix requests
tail -f log/development.log | grep "packages\|downloads\|installs"
```

## Production Deployment

### Docker Configuration

```dockerfile
FROM elixir:1.15-alpine

WORKDIR /app
COPY . .

# Configure HEX_MIRROR support
ENV HEX_HUB_URL=https://hexhub.your-domain.com
ENV STORAGE_TYPE=s3
ENV AWS_S3_BUCKET=your-hex-packages

RUN mix deps.get --only prod
RUN mix compile
RUN mix assets.deploy

EXPOSE 4000
CMD ["mix", "phx.server"]
```

### Nginx Reverse Proxy

```nginx
server {
    listen 80;
    server_name hexhub.your-domain.com;

    location / {
        proxy_pass http://localhost:4000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

## Performance Considerations

1. **Enable Caching**: Use CDN or caching proxies for better performance
2. **S3 Storage**: Consider S3 for production deployments
3. **Clustering**: Enable Mnesia clustering for high availability
4. **Monitoring**: Monitor package download metrics and error rates

## Security Notes

1. **API Keys**: Securely manage API keys for private packages
2. **HTTPS**: Use HTTPS in production environments
3. **Rate Limiting**: Configure appropriate rate limits
4. **Audit Logging**: Enable audit logging for security compliance

## Example Workflow

```bash
# 1. Start HexHub
mix phx.server

# 2. Configure Mix to use HexHub
export HEX_MIRROR=http://localhost:4000

# 3. Create a new Elixir project
mix new my_app
cd my_app

# 4. Add dependencies to mix.exs
defp deps do
  [
    {:phoenix, "~> 1.7.0"},
    {:ecto_sql, "~> 3.10"}
  ]
end

# 5. Fetch dependencies (will use HexHub)
mix deps.get

# 6. Check HexHub logs to see package requests
tail -f log/development.log
```

This setup allows you to use HexHub as a complete hex package mirror, providing offline capability, faster local access, and private package support.