# K8s Service Import — Design Spec

## Overview

Add the ability to import services from a live Kubernetes cluster into an Orbit environment. Users select a context, namespace, and one or more services — Orbit auto-generates the name, ports, and `kubectl port-forward` command for each.

## Entry Point

- New **"Import from K8s"** button in the environment detail view, next to the existing "Add Service" button
- Opens a sheet (`K8sImportSheet`) attached to the environment
- Sheet size: `width: 700, height: 550` (wider than AddServiceSheet to accommodate two-panel layout)

## Sheet Layout

### Top Bar

| Element | Behavior |
|---------|----------|
| **Context dropdown** | Populated via `kubectl config get-contexts -o name`. Defaults to current context (`kubectl config current-context`). Changing context cancels in-flight fetches and reloads namespaces. |
| **Tool toggle** | Segmented control: `kubectl` / `orb-kubectl`. Defaults to `kubectl`. If orb-kubectl is not installed (via `ToolManager`), show it disabled with tooltip "Not installed". The generated command uses the bare tool name (not absolute path) — this is safe because `ProcessManager` prepends Orbit's bin directory to PATH at runtime. |

### Two-Panel Body

| Panel | Content |
|-------|---------|
| **Left: Namespaces** | Searchable list. Fetched via `kubectl get ns -o json --context <ctx>`. Single-select. Selecting a namespace cancels in-flight service fetch and loads services in the right panel. |
| **Right: Services** | Searchable list with columns: checkbox, name, type (ClusterIP/NodePort/etc.), ports. Fetched via `kubectl get svc -n <ns> -o json --context <ctx>`. Multi-select via checkboxes. Services with zero ports (ExternalName, headless) are shown but not selectable (greyed out, no checkbox). |

### Footer

- Left: selection count ("3 services selected")
- Right: Cancel + "Import N Services" button (disabled when count is 0)

## Data Fetching

All data is fetched live via shell commands — no YAML parsing, no new dependencies.

| Data | Command | Parse |
|------|---------|-------|
| Contexts | `kubectl config get-contexts -o name` | Split by newline, filter empty |
| Current context | `kubectl config current-context` | Trim |
| Namespaces | `kubectl get ns -o json --context <ctx>` | JSON → `items[].metadata.name` |
| Services | `kubectl get svc -n <ns> -o json --context <ctx>` | JSON → `items[]` extracting name, type, ports |

### Execution Model

`KubernetesService` uses `Process` directly (not `ProcessManager`, which is for long-running service processes). All methods are `async` using Swift concurrency. Each fetch launches a `Process`, reads stdout/stderr via pipes, and decodes JSON with `JSONDecoder`.

- **Timeout**: 15 seconds per command. If exceeded, terminate the process and surface error.
- **Cancellation**: Uses Swift `Task` cancellation. Changing context cancels the namespace fetch task; changing namespace cancels the service fetch task; dismissing the sheet cancels all in-flight tasks.

### K8sService Model

```swift
struct K8sService: Identifiable, Hashable {
    let id = UUID()
    let name: String        // metadata.name
    let namespace: String   // metadata.namespace
    let type: String        // spec.type (ClusterIP, NodePort, etc.)
    let ports: [K8sPort]    // spec.ports[]

    var hasPorts: Bool { !ports.isEmpty }
}

struct K8sPort: Hashable {
    let port: Int               // spec.ports[].port
    let name: String?           // spec.ports[].name
    let transportProtocol: String  // spec.ports[].protocol (TCP/UDP)
}
```

### Error Handling

- **kubectl not found**: Show inline error "kubectl not found in PATH"
- **Context unreachable / timeout**: Show inline error with stderr output (truncated to 2 lines)
- **No namespaces / no services**: Show empty state text
- **Loading states**: Show spinner per panel while fetching

## Service Generation

For each selected K8s service, create an Orbit `Service`:

| Field | Value |
|-------|-------|
| `name` | K8s service name (e.g., `api-gateway`) |
| `ports` | Comma-joined port numbers from `spec.ports[].port` (e.g., `"8080,8443"`) |
| `command` | `<tool> port-forward --address $IP svc/<name> <port-mappings> -n <namespace> --context <context>` |
| `isEnabled` | `true` |
| `order` | Auto-assigned by `AppState.addService()` — appended in selection order |

### Duplicate Name Handling

If the environment already has a service with the same name, the imported service name is suffixed: `api-gateway` → `api-gateway-2`, `api-gateway-3`, etc. This matches the existing pattern for environment name deduplication.

### Port Mapping Format

Each port becomes `<port>:<port>` in the command. Multiple ports are space-separated:

```
kubectl port-forward --address $IP svc/elasticsearch 9200:9200 9300:9300 -n monitoring --context prod
```

### Command Template

```
{tool} port-forward --address $IP svc/{name} {ports} -n {namespace} --context {context}
```

Where:
- `{tool}` = `kubectl` or `orb-kubectl` (from toggle)
- `{name}` = K8s service `metadata.name`
- `{ports}` = space-separated `port:port` pairs
- `{namespace}` = selected namespace
- `{context}` = selected context

Commands always use `$IP` (first interface). Users can edit to `$IP2`/`$IP3` after import via EditServiceSheet.

### Validation

Generated values are programmatically constructed from K8s API output and guaranteed valid (service name is non-empty, ports are valid integers from the API, command is well-formed). No additional `ValidationService` validation is needed on import.

## New Files

| File | Purpose |
|------|---------|
| `orbit/Services/KubernetesService.swift` | Shell out to kubectl, parse JSON responses, return typed models |
| `orbit/Views/Sheets/K8sImportSheet.swift` | SwiftUI sheet with context/namespace/service selection UI |

XcodeGen auto-discovers files via directory glob in `project.yml` — no `project.yml` changes needed.

## Modified Files

| File | Change |
|------|--------|
| `orbit/Views/Components/EnvironmentDetailView.swift` (or equivalent) | Add "Import from K8s" button that opens the sheet |
| `orbit/ViewModels/AppState.swift` | No changes needed — uses existing `addService(to:service:)` |

## Architecture

```
K8sImportSheet (View)
  └── KubernetesService (fetching + parsing)
        └── kubectl / orb-kubectl (shell commands via Process)

User selects services → K8sImportSheet builds Service objects → calls appState.addService() for each
```

`KubernetesService` is a standalone class with no dependency on AppState. The sheet holds `@EnvironmentObject var appState` and calls `addService` on import.

## Testing

| Test | What it validates |
|------|-------------------|
| `testParseContexts` | Parsing `kubectl config get-contexts -o name` output |
| `testParseNamespaces` | Parsing `kubectl get ns -o json` response |
| `testParseServices` | Parsing `kubectl get svc -o json` response with various port configs (single, multi, zero ports) |
| `testCommandGeneration` | Correct command template for single-port, multi-port, orb-kubectl |
| `testServiceCreation` | K8sService → Orbit Service conversion with correct name/ports/command |
| `testDuplicateNameHandling` | Suffix generation when names collide |

Tests use static JSON fixtures — no live cluster required.

## Out of Scope

- Kubeconfig YAML parsing (we shell out to kubectl instead)
- Editing imported services before adding (user can edit after import via existing EditServiceSheet)
- Remembering last-used context/namespace (can add later)
- Pod or deployment selection (services only)
- Interface selection for multi-interface environments (defaults to $IP, editable after import)
