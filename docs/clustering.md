# HexHub Clustering Guide

This guide explains how to set up and manage Mnesia clustering for high availability in HexHub.

## Overview

HexHub supports Mnesia clustering to provide:
- **High Availability**: Data is replicated across multiple nodes
- **Load Distribution**: Requests can be handled by any cluster node
- **Fault Tolerance**: If one node fails, others continue serving requests
- **Scalability**: Add more nodes as your registry grows

## Quick Start

### 1. Single Node Development

For development, no clustering is required:

```bash
# Start a single node
mix phx.server
# or
./scripts/cluster.sh start
```

### 2. Multi-Node Cluster

#### Option A: Using the Cluster Script

**Terminal 1 - Start first node:**
```bash
PORT=4000 NODE_NAME=hex_hub1 ./scripts/cluster.sh start
```

**Terminal 2 - Start second node:**
```bash
PORT=4001 NODE_NAME=hex_hub2 ./scripts/cluster.sh start
```

**Terminal 3 - Start third node:**
```bash
PORT=4002 NODE_NAME=hex_hub3 ./scripts/cluster.sh start
```

**Join nodes to cluster:**
```bash
# From hex_hub2 node
./scripts/cluster.sh join hex_hub1@127.0.0.1

# From hex_hub3 node  
./scripts/cluster.sh join hex_hub1@127.0.0.1
```

#### Option B: Manual Clustering

**Step 1: Start nodes with proper names**

```bash
# Node 1
iex --name hex_hub1@127.0.0.1 --cookie hex_hub_cluster -S mix phx.server --port 4000

# Node 2  
iex --name hex_hub2@127.0.0.1 --cookie hex_hub_cluster -S mix phx.server --port 4001

# Node 3
iex --name hex_hub3@127.0.0.1 --cookie hex_hub_cluster -S mix phx.server --port 4002
```

**Step 2: Configure clustering via API**

```bash
# Join hex_hub2 to hex_hub1
curl -X POST http://localhost:4001/api/cluster/join \
  -H "Content-Type: application/json" \
  -d '{"node": "hex_hub1@127.0.0.1"}'

# Join hex_hub3 to hex_hub1  
curl -X POST http://localhost:4002/api/cluster/join \
  -H "Content-Type: application/json" \
  -d '{"node": "hex_hub1@127.0.0.1"}'
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLUSTERING_ENABLED` | `false` | Enable Mnesia clustering |
| `CLUSTER_NODES` | `""` | Comma-separated list of cluster nodes |
| `CLUSTER_DISCOVERY_TYPE` | `"epmd"` | Discovery method: `"epmd"`, `"dns"`, `"static"` |
| `CLUSTER_DNS_HOSTNAME` | - | DNS hostname for SRV discovery |
| `REPLICATION_FACTOR` | `2` | Number of nodes to replicate data across |
| `MNESIA_DIR` | `./mnesia/#{node()}` | Mnesia data directory |
| `HEARTBEAT_INTERVAL` | `5000` | Node health check interval (ms) |
| `HEARTBEAT_TIMEOUT` | `10000` | Node health check timeout (ms) |

### Configuration File

Edit `config/clustering.exs` to customize clustering behavior:

```elixir
config :hex_hub, :clustering,
  enabled: true,
  replication_factor: 3,
  discovery: %{
    type: "static",
    nodes: ["hex_hub1@127.0.0.1", "hex_hub2@127.0.0.1"]
  }
```

## Cluster Management

### Check Cluster Status

```bash
# Via script
./scripts/cluster.sh status

# Via API
curl http://localhost:4000/api/cluster/status | jq .
```

### Leave Cluster

```bash
# Via script
./scripts/cluster.sh leave

# Via API
curl -X POST http://localhost:4000/api/cluster/leave
```

## Docker Deployment

### Docker Compose Example

Create `docker-compose.yml`:

```yaml
version: '3.8'
services:
  hex_hub1:
    build: .
    ports:
      - "4000:4000"
    environment:
      - CLUSTERING_ENABLED=true
      - NODE_NAME=hex_hub1@hex_hub1
      - PORT=4000
      - COOKIE=hex_hub_cluster
    networks:
      - hex_hub_network

  hex_hub2:
    build: .
    ports:
      - "4001:4000"
    environment:
      - CLUSTERING_ENABLED=true
      - NODE_NAME=hex_hub2@hex_hub2
      - PORT=4000
      - COOKIE=hex_hub_cluster
      - CLUSTER_NODES=hex_hub1@hex_hub1,hex_hub2@hex_hub2
    depends_on:
      - hex_hub1
    networks:
      - hex_hub_network

  hex_hub3:
    build: .
    ports:
      - "4002:4000"
    environment:
      - CLUSTERING_ENABLED=true
      - NODE_NAME=hex_hub3@hex_hub3
      - PORT=4000
      - COOKIE=hex_hub_cluster
      - CLUSTER_NODES=hex_hub1@hex_hub1,hex_hub2@hex_hub2,hex_hub3@hex_hub3
    depends_on:
      - hex_hub1
      - hex_hub2
    networks:
      - hex_hub_network

networks:
  hex_hub_network:
    driver: bridge
```

### Kubernetes Deployment

For Kubernetes, use a StatefulSet with DNS discovery:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: hex-hub
spec:
  serviceName: hex-hub
  replicas: 3
  template:
    spec:
      containers:
      - name: hex-hub
        image: hex-hub:latest
        env:
        - name: CLUSTERING_ENABLED
          value: "true"
        - name: CLUSTER_DISCOVERY_TYPE
          value: "dns"
        - name: CLUSTER_DNS_HOSTNAME
          value: "hex-hub.default.svc.cluster.local"
```

## Monitoring and Troubleshooting

### Health Checks

The cluster health can be monitored via:
- `/health` - Basic health check
- `/health/ready` - Readiness probe for Kubernetes
- `/health/live` - Liveness probe for Kubernetes
- `/api/cluster/status` - Detailed cluster status

### Common Issues

**1. Nodes can't connect:**
- Check firewall settings (ports 4369 for EPMD, 9100-9155 for Erlang distribution)
- Verify all nodes use the same cookie (`COOKIE` environment variable)
- Ensure DNS is working for hostname resolution

**2. Data not replicating:**
- Check `REPLICATION_FACTOR` is not greater than the number of nodes
- Verify Mnesia tables are properly configured with `Clustering.get_cluster_status()`
- Check disk space and permissions for Mnesia directories

**3. Split-brain scenario:**
- Restart affected nodes with proper clustering configuration
- Use `Clustering.leave_cluster()` to remove problematic nodes
- Re-join nodes in the correct order

### Performance Tuning

**Replication Settings:**
- Increase `REPLICATION_FACTOR` for better fault tolerance (but increases write latency)
- Use `CLUSTER_DISCOVERY_TYPE: "dns"` for dynamic scaling in cloud environments

**Network Settings:**
- Tune `HEARTBEAT_INTERVAL` and `HEARTBEAT_TIMEOUT` based on network latency
- Use dedicated network interfaces for cluster communication if possible

## API Reference

### Cluster Management Endpoints

- `GET /api/cluster/status` - Get cluster status
- `POST /api/cluster/join` - Join a cluster (body: `{"node": "nodename@host"}`)
- `POST /api/cluster/leave` - Leave the current cluster

## Best Practices

1. **Start with 3 nodes** minimum for proper fault tolerance
2. **Use consistent node names** across restarts
3. **Monitor disk usage** on all nodes
4. **Test failover scenarios** regularly
5. **Use load balancers** to distribute requests across nodes
6. **Back up Mnesia directories** regularly
7. **Use EPMD discovery** for simple setups, DNS for cloud deployments