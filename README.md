# HexHub - Private Hex Package Manager

[![CI](https://github.com/gsmlg-dev/hex_hub/actions/workflows/ci.yml/badge.svg)](https://github.com/gsmlg-dev/hex_hub/actions/workflows/ci.yml)
[![Test](https://github.com/gsmlg-dev/hex_hub/actions/workflows/test.yml/badge.svg)](https://github.com/gsmlg-dev/hex_hub/actions/workflows/test.yml)
[![E2E Tests](https://github.com/gsmlg-dev/hex_hub/actions/workflows/e2e.yml/badge.svg)](https://github.com/gsmlg-dev/hex_hub/actions/workflows/e2e.yml)
[![Docker Image](https://ghcr-badge.egpl.dev/gsmlg-dev/hex-hub/latest_tag?trim=major&label=docker&color=blue)](https://github.com/gsmlg-dev/hex_hub/pkgs/container/hex-hub)

HexHub is a complete implementation of the Hex API specification for managing Elixir packages privately. It provides package hosting, documentation serving, and repository management capabilities.

## Features

- **Complete Hex API Compatibility**: Drop-in replacement for hex.pm
- **Package Management**: Upload, download, and manage Elixir packages
- **Documentation Hosting**: Automatic documentation generation and serving
- **User Management**: API key authentication and user accounts
- **Repository Support**: Private repositories with access control
- **Live Documentation**: Real-time documentation updates
- **Mnesia Storage**: In-memory database with disk persistence (no PostgreSQL required)
- **Flexible Storage**: Support for local filesystem or S3-compatible storage
- **Zero Database Setup**: Uses Mnesia for data storage, no external database required
- **Anonymous Publishing**: Optional mode for publishing packages without authentication (configurable via admin dashboard)
- **Admin Dashboard**: Web-based administration interface for managing users, packages, and configuration

## Status

✅ **Development Complete**: All core Hex API functionality has been implemented with Mnesia storage.

**Completed Features:**
- ✅ Complete Hex API implementation
- ✅ Mnesia database with full CRUD operations
- ✅ User management with authentication
- ✅ Package publishing and retrieval
- ✅ Documentation hosting
- ✅ API key management
- ✅ Package ownership management
- ✅ Comprehensive test suite (389+ tests, 100% passing)
- ✅ Local file storage for packages and documentation
- ✅ Anonymous publishing mode (admin configurable)
- ✅ Admin dashboard with user/package management

The application is ready for production use.

## Quick Start

### Prerequisites

- Elixir 1.15+ and Erlang/OTP 26+
- Node.js 18+ (for assets)
- No database required (uses Mnesia for storage)

### Installation

```bash
# Clone the repository
git clone https://github.com/gsmlg-dev/hex_hub.git
cd hex_hub

# Install dependencies
mix setup

# Start the development server
mix phx.server
```

The application will be available at `http://localhost:4000`

### Production Deployment

```bash
# Build for production
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release

# Run the release
_build/prod/rel/hex_hub/bin/hex_hub start
```

## API Usage

### Authentication

All API endpoints require authentication via API key:

```bash
curl -H "Authorization: Bearer YOUR_API_KEY" https://your-domain.com/api/packages
```

### Publishing Packages

```bash
# Create a package first
curl -X POST \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"repository": "hexpm", "meta": {"description": "My awesome package"}}' \
  https://your-domain.com/api/packages/my_package

# Then publish a release
curl -X POST \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @my_package-1.0.0.tar \
  https://your-domain.com/api/publish?name=my_package&version=1.0.0
```

### Installing Packages

Add to your `mix.exs`:

```elixir
defp deps do
  [
    {:my_package, "~> 1.0", repo: "gsmlg-dev", organization: "gsmlg-dev"}
  ]
end
```

Configure your repository:

```elixir
# In config/config.exs
config :hex, repos: [
  "gsmlg-dev": "https://your-domain.com"
]
```

## API Endpoints

The application implements the complete Hex API specification:

### Users
- `POST /api/users` - Create new user
- `GET /api/users/:username_or_email` - Get user profile
- `GET /api/users/me` - Get current authenticated user
- `POST /api/users/:username_or_email/reset` - Reset password

### Repositories
- `GET /api/repos` - List repositories
- `GET /api/repos/:name` - Get repository details

### Packages
- `GET /api/packages` - List packages (with pagination and search)
- `GET /api/packages/:name` - Get package details
- `POST /api/publish` - Publish new package/release

### Documentation
- `POST /api/packages/:name/releases/:version/docs` - Upload documentation
- `DELETE /api/packages/:name/releases/:version/docs` - Remove documentation

### Package Ownership
- `GET /api/packages/:name/owners` - List package owners
- `PUT /api/packages/:name/owners/:email` - Add package owner
- `DELETE /api/packages/:name/owners/:email` - Remove package owner

### API Keys
- `GET /api/keys` - List API keys
- `POST /api/keys` - Create API key (requires Basic Auth)
- `GET /api/keys/:name` - Get API key details
- `DELETE /api/keys/:name` - Delete API key

## Configuration

### Environment Variables

- `SECRET_KEY_BASE`: 64-byte secret for sessions
- `PHX_HOST`: Hostname for URL generation
- `MIX_ENV`: Environment (dev, test, prod)

### Storage Configuration

Configure storage in `config/dev.exs`:

```elixir
config :hex_hub,
  storage_type: :local,  # or :s3
  storage_path: "priv/storage"
```

For S3 storage:
```elixir
config :hex_hub,
  storage_type: :s3,
  s3_bucket: "your-bucket-name",
  s3_region: "us-east-1"

# S3 Configuration
config :ex_aws,
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  region: System.get_env("AWS_REGION", "us-east-1")

config :ex_aws, :s3,
  scheme: "https://",
  host: System.get_env("AWS_S3_HOST"),  # For custom S3-compatible services
  port: (if port = System.get_env("AWS_S3_PORT"), do: String.to_integer(port), else: 443),
  path_style: System.get_env("AWS_S3_PATH_STYLE", "false") == "true"
```

### S3 Storage Setup

#### AWS S3 Setup

1. Create an S3 bucket:
   ```bash
   aws s3 mb s3://your-hex-packages-bucket
   ```

2. Create an IAM user with programmatic access and attach the following policy:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "s3:GetObject",
           "s3:PutObject",
           "s3:DeleteObject",
           "s3:ListBucket"
         ],
         "Resource": [
           "arn:aws:s3:::your-hex-packages-bucket",
           "arn:aws:s3:::your-hex-packages-bucket/*"
         ]
       }
     ]
   }
   ```

3. Set environment variables:
   ```bash
   export STORAGE_TYPE=s3
   export S3_BUCKET=your-hex-packages-bucket
   export AWS_ACCESS_KEY_ID=your-access-key
   export AWS_SECRET_ACCESS_KEY=your-secret-key
   export AWS_REGION=us-east-1
   ```

#### S3-Compatible Services (MinIO, DigitalOcean Spaces, etc.)

For S3-compatible services, use additional environment variables:

```bash
export AWS_S3_HOST=your-minio-server.com
export AWS_S3_PORT=9000
export AWS_S3_PATH_STYLE=true  # Required for MinIO
export AWS_S3_SCHEME=http  # Use http for local MinIO
```

#### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `STORAGE_TYPE` | Storage backend (`local` or `s3`) | `local` |
| `S3_BUCKET` | S3 bucket name | - |
| `AWS_ACCESS_KEY_ID` | AWS access key ID | - |
| `AWS_SECRET_ACCESS_KEY` | AWS secret access key | - |
| `AWS_REGION` | AWS region | `us-east-1` |
| `AWS_S3_HOST` | Custom S3 host (for S3-compatible services) | - |
| `AWS_S3_PORT` | Custom S3 port | `443` |
| `AWS_S3_PATH_STYLE` | Use path-style addressing (for MinIO) | `false` |
| `AWS_S3_SCHEME` | URL scheme (`http` or `https`) | `https` |

### Repository Settings

Configure repositories in `config/runtime.exs`:

```elixir
config :hex_hub, :repositories, [
  %{
    name: "my-org",
    private: true,
    public_key: "base64-encoded-public-key"
  }
]
```

## Development

### Running Tests

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run specific test file
mix test test/hex_hub_web/controllers/api/package_controller_test.exs
```

### Database Setup

No database setup required - HexHub uses Mnesia for data storage. Mnesia will automatically initialize on first run.

For testing:
```bash
# Mnesia will be automatically configured for tests
# No manual setup needed
```

### Code Style

```bash
# Format code
mix format

# Check for issues
mix credo

# Type checking (if using dialyzer)
mix dialyzer
```

## Production Deployment

For production deployment:

1. Configure Mnesia clustering if needed
2. Set up persistent storage for Mnesia data
3. Configure SSL/TLS
4. Set up monitoring and logging
5. Configure file storage (local or S3)

### Mnesia Configuration

HexHub uses Mnesia for data storage. Data is stored in:
- `Mnesia.<node_name>/` directory for Mnesia tables
- `priv/storage/` directory for package and documentation files

For persistence, ensure these directories are backed up and restored as needed.

### Docker Deployment

Pre-built Docker images are available on GitHub Container Registry:

```bash
# Pull the latest image
docker pull ghcr.io/gsmlg-dev/hex-hub:main

# Run with basic configuration
docker run -d \
  --name hex-hub \
  -p 4000:4000 \
  -p 4001:4001 \
  -e SECRET_KEY_BASE=$(openssl rand -base64 48) \
  -e PHX_HOST=localhost \
  -v hex_hub_data:/app/priv/storage \
  -v hex_hub_mnesia:/app/Mnesia.hex_hub@localhost \
  ghcr.io/gsmlg-dev/hex-hub:main
```

Or use Docker Compose:

```yaml
version: '3.8'
services:
  hex-hub:
    image: ghcr.io/gsmlg-dev/hex-hub:main
    ports:
      - "4000:4000"   # Main API
      - "4001:4001"   # Admin dashboard
    environment:
      - SECRET_KEY_BASE=${SECRET_KEY_BASE}
      - PHX_HOST=${PHX_HOST:-localhost}
    volumes:
      - hex_hub_data:/app/priv/storage
      - hex_hub_mnesia:/app/Mnesia.hex_hub@localhost

volumes:
  hex_hub_data:
  hex_hub_mnesia:
```

For building from source:

```dockerfile
FROM elixir:1.18-alpine

WORKDIR /app
COPY . .

RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get && \
    mix compile && \
    mix assets.deploy

EXPOSE 4000 4001
CMD ["mix", "phx.server"]
```

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -am 'Add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

## Security

- Use strong API keys
- Enable HTTPS in production
- Implement rate limiting
- Regular security audits
- Monitor access logs

## License

MIT License - see [LICENSE](LICENSE) for details.

## Support

- [GitHub Issues](https://github.com/gsmlg-dev/hex_hub/issues)
- [Documentation](https://your-docs-site.com)
- [Community Discord](https://discord.gg/your-server)