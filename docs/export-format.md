# Orbit Export File Format

This document describes the `.orbit.json` file format used for importing and exporting environment configurations.

## Overview

Orbit environments can be exported to JSON files with the `.orbit.json` extension. These files contain all the configuration needed to recreate an environment, including:

- Environment name
- Interface IP addresses
- Service definitions (name, ports, command, enabled state, order)

Runtime state (process status, logs, errors) is **not** included in exports.

## File Structure

```json
{
  "version": "1.0",
  "exportedAt": "2025-12-25T07:07:10Z",
  "environment": {
    "name": "My Environment",
    "interfaces": ["127.0.0.2"],
    "services": [
      {
        "name": "service-name",
        "ports": "8080",
        "command": "kubectl port-forward --address $IP svc/my-service 8080:8080",
        "isEnabled": true,
        "order": 0
      }
    ]
  }
}
```

## Field Reference

### Root Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `version` | string | Yes | Format version. Currently `"1.0"` |
| `exportedAt` | string | Yes | ISO 8601 timestamp of when the file was exported |
| `environment` | object | Yes | The environment configuration |

### Environment Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Display name of the environment |
| `interfaces` | array | Yes | List of loopback IP addresses (e.g., `["127.0.0.2", "127.0.0.3"]`) |
| `services` | array | Yes | List of service configurations |

### Service Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Display name of the service |
| `ports` | string | Yes | Port numbers for display (e.g., `"8080"`, `"80,443"`) |
| `command` | string | Yes | Shell command to run. Supports variable substitution |
| `isEnabled` | boolean | Yes | Whether the service starts when the environment is activated |
| `order` | integer | Yes | Sort order for display (0-based) |

## Variable Substitution

Commands support the following variables that resolve to the environment's interface IPs:

| Variable | Resolves To |
|----------|-------------|
| `$IP` | First interface (`interfaces[0]`) |
| `$IP2` | Second interface (`interfaces[1]`) |
| `$IP3` | Third interface (`interfaces[2]`) |
| `$IPn` | nth interface (`interfaces[n-1]`) |

## Examples

### Single Service Environment

```json
{
  "version": "1.0",
  "exportedAt": "2025-12-25T07:07:10Z",
  "environment": {
    "name": "Claymore-DEV",
    "interfaces": ["127.0.0.2"],
    "services": [
      {
        "name": "dcmp-pg",
        "ports": "5432",
        "command": "kubectl port-forward --address $IP svc/dcmp-postgres-primary 5432:5432 --context claymore-dev",
        "isEnabled": true,
        "order": 0
      }
    ]
  }
}
```

### Multi-Service Environment

```json
{
  "version": "1.0",
  "exportedAt": "2025-12-25T10:30:00Z",
  "environment": {
    "name": "Production-Like",
    "interfaces": ["127.0.0.10", "127.0.0.11"],
    "services": [
      {
        "name": "api-gateway",
        "ports": "8080",
        "command": "kubectl port-forward --address $IP svc/api-gateway 8080:8080 --context prod-cluster",
        "isEnabled": true,
        "order": 0
      },
      {
        "name": "postgres",
        "ports": "5432",
        "command": "ssh -N -L $IP:5432:db.internal:5432 user@bastion.example.com",
        "isEnabled": true,
        "order": 1
      },
      {
        "name": "redis",
        "ports": "6379",
        "command": "kubectl port-forward --address $IP2 svc/redis 6379:6379 --context prod-cluster",
        "isEnabled": false,
        "order": 2
      }
    ]
  }
}
```

### Cloudflare Tunnel Example

```json
{
  "version": "1.0",
  "exportedAt": "2025-12-25T12:00:00Z",
  "environment": {
    "name": "Remote-Services",
    "interfaces": ["127.0.0.50"],
    "services": [
      {
        "name": "internal-api",
        "ports": "443",
        "command": "cloudflared access tcp --hostname $IP --url internal-api.example.com 443",
        "isEnabled": true,
        "order": 0
      }
    ]
  }
}
```

## Import Behavior

When importing an `.orbit.json` file, Orbit handles conflicts automatically:

### Name Conflicts
If an environment with the same name already exists, Orbit suggests appending `" (Imported)"` to the name. You can edit the name before importing.

### IP Conflicts
If any interface IPs are already in use by another environment, Orbit:
1. Highlights the conflicting IPs
2. Suggests the next available IPs
3. Lets you choose to use suggested IPs or keep originals

### Fresh UUIDs
All imported environments and services receive new UUIDs. Importing never overwrites existing configurations.

## Validation

On import, Orbit validates:

- JSON syntax
- Required fields present
- Version compatibility (currently only `"1.0"`)
- IP address format (must be valid IPv4 in 127.x.x.x range)
- At least one interface defined

Invalid files show a descriptive error message explaining the issue.
