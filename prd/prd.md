# DEV Fwd - AI-Optimized Product Requirements Document

## META
```yaml
project_name: "DEV Fwd"
platform: macOS
min_os_version: "13.0"
language: Swift
ui_framework: SwiftUI
architecture: MVVM
bundle_id: "com.devfwd.app"
```

---

## DATA_MODELS

### Environment
```swift
struct Environment: Identifiable, Codable {
    let id: UUID
    var name: String                    // non-empty, unique across all environments
    var interfaces: [String]            // min 1 item, each must match 127\.(\d{1,3})\.(\d{1,3})\.(\d{1,3}), unique globally
    var services: [Service]
    var isEnabled: Bool                 // runtime state, not persisted
    var order: Int                      // for sidebar ordering
}

// Constraints:
// - name.isEmpty == false
// - name must be unique across AppState.environments
// - interfaces.count >= 1
// - each interface must be unique across ALL environments (not just this one)
// - interfaces[0] -> "$IP", interfaces[1] -> "$IP2", interfaces[2] -> "$IP3", etc.
```

### Service
```swift
struct Service: Identifiable, Codable {
    let id: UUID
    var name: String                    // non-empty
    var ports: String                   // display only, format: "8080" or "80,443,8080"
    var command: String                 // non-empty, may contain $IP, $IP2, $IP3 variables
    var isEnabled: Bool                 // whether to start when environment activates
    var order: Int                      // startup order within environment
    
    // Runtime state (not persisted):
    var status: ServiceStatus
    var restartCount: Int
    var lastError: String?
    var logs: [LogEntry]
}

// Constraints:
// - name.isEmpty == false
// - ports must match: ^\d+(,\d+)*$ where each number is 1-65535
// - command.isEmpty == false
```

### ServiceStatus
```swift
enum ServiceStatus: String, Codable {
    case stopped    // gray indicator
    case starting   // yellow pulsing indicator
    case running    // green indicator
    case failed     // red indicator
    case stopping   // yellow indicator
}
```

### LogEntry
```swift
struct LogEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let message: String
    let stream: LogStream
}

enum LogStream {
    case stdout
    case stderr
}
```

### AppState
```swift
class AppState: ObservableObject {
    @Published var environments: [Environment]
    @Published var guestMode: Bool
    @Published var selectedEnvironmentId: UUID?
    
    var authorizationRef: AuthorizationRef?  // cached sudo authorization
}
```

### Persisted Configuration
```json
{
  "version": "1.0",
  "environments": [
    {
      "id": "uuid-string",
      "name": "string",
      "interfaces": ["127.0.0.2", "127.0.0.3"],
      "services": [
        {
          "id": "uuid-string",
          "name": "string",
          "ports": "string",
          "command": "string",
          "isEnabled": true,
          "order": 0
        }
      ],
      "order": 0
    }
  ],
  "settings": {
    "launchAtLogin": false
  }
}
```

Storage path: `~/Library/Application Support/DEV Fwd/config.json`

---

## VARIABLE_SUBSTITUTION

### Resolution Rules
```
interfaces[0] -> $IP
interfaces[1] -> $IP2
interfaces[2] -> $IP3
interfaces[n] -> $IP{n+1} (for n > 0)
```

### Implementation
```swift
func resolveCommand(_ command: String, interfaces: [String]) -> String {
    var result = command
    for (index, ip) in interfaces.enumerated() {
        let variable = index == 0 ? "$IP" : "$IP\(index + 1)"
        result = result.replacingOccurrences(of: variable, with: ip)
    }
    return result
}
```

---

## STATE_MACHINES

### Environment Lifecycle
```
States: [inactive, activating, active, deactivating]

Transitions:
  inactive -> activating     : user toggles ON
  activating -> active       : all interfaces up AND all enabled services started
  activating -> inactive     : interface up failed (rollback)
  active -> deactivating     : user toggles OFF
  deactivating -> inactive   : all services stopped AND all interfaces down
```

### Service Lifecycle
```
States: [stopped, starting, running, failed, stopping]

Transitions:
  stopped -> starting        : parent environment activates AND service.isEnabled
  starting -> running        : process alive for 3 seconds
  starting -> failed         : process exits before 3 seconds
  running -> failed          : process exits unexpectedly
  running -> stopping        : user stops OR parent environment deactivates
  stopping -> stopped        : process terminated (SIGTERM then SIGKILL)
  failed -> starting         : auto-restart triggered (with backoff)
  failed -> stopped          : user manually stops OR max restarts exceeded
  stopped -> starting        : user manually starts (when env is active)
```

### Auto-Restart Logic
```swift
struct RestartPolicy {
    static let maxAttempts = 10
    static let baseDelay: TimeInterval = 1.0
    static let maxDelay: TimeInterval = 30.0
    static let resetAfterStable: TimeInterval = 60.0
    
    static func delay(forAttempt attempt: Int) -> TimeInterval {
        min(pow(2.0, Double(attempt - 1)) * baseDelay, maxDelay)
    }
}

// Backoff sequence: 1s, 2s, 4s, 8s, 16s, 30s, 30s, 30s, 30s, 30s (then stop)
// Reset restartCount to 0 after 60s of stable running
```

---

## OPERATIONS

### OP_001: Create Environment
```yaml
trigger: user clicks "+ New Environment"
preconditions: none
steps:
  1. Generate new UUID
  2. Create Environment with:
     - id: generated UUID
     - name: "New Environment" (editable inline)
     - interfaces: ["127.0.0.2"] (suggest next available)
     - services: []
     - isEnabled: false
     - order: environments.count
  3. Add to AppState.environments
  4. Select new environment in sidebar
  5. Focus name field for editing
  6. Persist to disk
postconditions:
  - New environment visible in sidebar
  - Environment selected and editable
validation:
  - Suggest next available IP (scan existing interfaces, find gap in 127.0.0.x)
```

### OP_002: Add Interface to Environment
```yaml
trigger: user clicks "+ Add Interface" in interface list
preconditions:
  - Environment is not active (isEnabled == false)
steps:
  1. Suggest next available IP in 127.0.0.0/8 range
  2. Add IP to environment.interfaces array
  3. Update UI to show new interface with variable name
  4. Persist to disk
postconditions:
  - New interface visible with auto-assigned variable ($IP2, $IP3, etc.)
validation:
  - IP must be valid 127.x.x.x format
  - IP must not exist in ANY environment
```

### OP_003: Remove Interface from Environment
```yaml
trigger: user clicks "✕" on interface row
preconditions:
  - Environment is not active
  - interfaces.count > 1 (cannot remove last interface)
steps:
  1. Check if variable is used in any service command
  2. If used: show warning "Variable $IPn is used in services: [list]. Remove anyway?"
  3. If confirmed or not used: remove from interfaces array
  4. Reindex remaining interfaces (variables shift)
  5. Persist to disk
postconditions:
  - Interface removed
  - Remaining interfaces renumbered
warnings:
  - Variable renumbering may break commands using higher-numbered variables
```

### OP_004: Add Service
```yaml
trigger: user clicks "+ Add Service" button
preconditions:
  - Environment selected
ui: modal sheet
fields:
  - name: String, required, placeholder "e.g. auth-service, payment-gateway"
  - ports: String, required, placeholder "e.g. 8080 or 80,443,8080"
  - command: String (multiline), required, placeholder "# Enter startup command\nkubectl port-forward --address $IP svc/name 8080:8080"
steps:
  1. Show modal with empty fields
  2. Show available variables hint: "💡 Variables: $IP → 127.0.0.2  $IP2 → 127.0.0.3"
  3. On Save:
     a. Validate all fields non-empty
     b. Validate ports format
     c. Create Service with isEnabled: true, order: services.count
     d. Add to environment.services
     e. Persist to disk
  4. Close modal
postconditions:
  - Service added to environment
  - Service visible in service list
```

### OP_005: Activate Environment
```yaml
trigger: user toggles environment checkbox ON (in sidebar or menubar)
preconditions:
  - Environment.isEnabled == false
  - All interfaces valid
steps:
  1. Check/acquire sudo authorization (prompt if needed)
  2. For each interface in environment.interfaces:
     a. Execute: sudo ifconfig lo0 alias {IP} up
     b. If fails: rollback (remove already-added aliases), show error, abort
  3. Set environment.isEnabled = true
  4. For each service in environment.services where service.isEnabled == true (ordered by service.order):
     a. Set service.status = .starting
     b. Resolve command variables
     c. Spawn process (see PROCESS_MANAGEMENT)
postconditions:
  - All interfaces aliased to lo0
  - All enabled services starting/running
rollback:
  - On interface failure: remove all aliases added in this operation
  - On service failure: continue with other services (don't rollback interfaces)
```

### OP_006: Deactivate Environment
```yaml
trigger: user toggles environment checkbox OFF
preconditions:
  - Environment.isEnabled == true
steps:
  1. For each running service:
     a. Set service.status = .stopping
     b. Send SIGTERM to process
     c. Wait up to 5 seconds
     d. If still running: send SIGKILL
     e. Set service.status = .stopped
     f. Reset service.restartCount = 0
  2. For each interface in environment.interfaces:
     a. Execute: sudo ifconfig lo0 -alias {IP}
  3. Set environment.isEnabled = false
postconditions:
  - All services stopped
  - All interfaces removed from lo0
```

### OP_007: Toggle Individual Service
```yaml
trigger: user toggles service checkbox
case service_enabled_to_disabled:
  preconditions: service.isEnabled == true
  steps:
    1. Set service.isEnabled = false
    2. If environment.isEnabled AND service.status in [starting, running]:
       a. Stop process (SIGTERM, wait 5s, SIGKILL)
       b. Set service.status = .stopped
    3. Persist
    
case service_disabled_to_enabled:
  preconditions: service.isEnabled == false
  steps:
    1. Set service.isEnabled = true
    2. If environment.isEnabled:
       a. Set service.status = .starting
       b. Spawn process
    3. Persist
```

### OP_008: View Service Logs
```yaml
trigger: user clicks "View Logs" in service context menu OR clicks error badge
ui: sheet overlay
content:
  - Header: "Logs: {service.name}" + Close button
  - Log area: ScrollView with monospace text, always scrolled to bottom
  - Footer: [📋 Copy All] [🗑 Clear] buttons
behavior:
  - Auto-scroll to bottom on new entries
  - Max 10,000 entries (ring buffer - oldest removed when exceeded)
  - Timestamps format: [HH:mm:ss]
  - Combined stdout/stderr (stderr could be colored red optionally)
actions:
  - Copy All: copy all log text to clipboard
  - Clear: remove all entries from service.logs
```

---

## PROCESS_MANAGEMENT

### Spawn Process
```swift
func spawnProcess(service: Service, interfaces: [String]) -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", resolveCommand(service.command, interfaces: interfaces)]
    process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
    
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    
    // Capture stdout
    outputPipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if let str = String(data: data, encoding: .utf8), !str.isEmpty {
            appendLog(service: service, message: str, stream: .stdout)
        }
    }
    
    // Capture stderr
    errorPipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if let str = String(data: data, encoding: .utf8), !str.isEmpty {
            appendLog(service: service, message: str, stream: .stderr)
        }
    }
    
    // Monitor termination
    process.terminationHandler = { proc in
        handleProcessExit(service: service, exitCode: proc.terminationStatus)
    }
    
    try? process.run()
    return process
}
```

### Handle Process Exit
```swift
func handleProcessExit(service: Service, exitCode: Int32) {
    if service.status == .stopping {
        // Expected exit - user stopped it
        service.status = .stopped
        return
    }
    
    // Unexpected exit
    service.lastError = "Exited with code \(exitCode)"
    
    if service.restartCount >= RestartPolicy.maxAttempts {
        service.status = .failed
        return
    }
    
    // Schedule restart with backoff
    let delay = RestartPolicy.delay(forAttempt: service.restartCount + 1)
    service.restartCount += 1
    
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        if service.isEnabled && service.parentEnvironment.isEnabled {
            service.status = .starting
            spawnProcess(service: service, interfaces: service.parentEnvironment.interfaces)
        }
    }
}
```

### Process Termination
```swift
func stopProcess(service: Service) {
    guard let process = service.process, process.isRunning else { return }
    
    service.status = .stopping
    
    // Send SIGTERM
    process.terminate()
    
    // Wait up to 5 seconds
    DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
        if process.isRunning {
            // Force kill
            kill(process.processIdentifier, SIGKILL)
        }
        service.status = .stopped
        service.restartCount = 0
    }
}
```

---

## PRIVILEGE_MANAGEMENT

### Authorization Flow
```swift
// On first privileged operation:
func acquireAuthorization() throws -> AuthorizationRef {
    if let existing = appState.authorizationRef {
        return existing
    }
    
    var auth: AuthorizationRef?
    let status = AuthorizationCreate(nil, nil, [], &auth)
    
    guard status == errAuthorizationSuccess, let auth = auth else {
        throw PrivilegeError.authorizationFailed
    }
    
    appState.authorizationRef = auth
    return auth
}

// Execute privileged command using osascript (MVP approach):
func executePrivileged(_ command: String) throws {
    let script = "do shell script \"\(command)\" with administrator privileges"
    var error: NSDictionary?
    
    if let scriptObject = NSAppleScript(source: script) {
        scriptObject.executeAndReturnError(&error)
        if let error = error {
            throw PrivilegeError.executionFailed(error.description)
        }
    }
}

// Interface operations:
func bringUpInterface(_ ip: String) throws {
    try executePrivileged("ifconfig lo0 alias \(ip) up")
}

func bringDownInterface(_ ip: String) throws {
    try executePrivileged("ifconfig lo0 -alias \(ip)")
}
```

---

## VALIDATION_RULES

### IP Address
```swift
func validateIP(_ ip: String) -> ValidationResult {
    let pattern = #"^127\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          regex.firstMatch(in: ip, range: NSRange(ip.startIndex..., in: ip)) != nil else {
        return .invalid("Must be in format 127.x.x.x")
    }
    
    let components = ip.split(separator: ".").compactMap { Int($0) }
    guard components.count == 4,
          components.allSatisfy({ $0 >= 0 && $0 <= 255 }) else {
        return .invalid("Each octet must be 0-255")
    }
    
    return .valid
}

func validateIPUniqueness(_ ip: String, excluding environmentId: UUID?) -> ValidationResult {
    let allIPs = appState.environments
        .filter { $0.id != environmentId }
        .flatMap { $0.interfaces }
    
    if allIPs.contains(ip) {
        return .invalid("IP already used by another environment")
    }
    
    return .valid
}
```

### Ports
```swift
func validatePorts(_ ports: String) -> ValidationResult {
    let portStrings = ports.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    
    guard !portStrings.isEmpty else {
        return .invalid("At least one port required")
    }
    
    for portStr in portStrings {
        guard let port = Int(portStr), port >= 1, port <= 65535 else {
            return .invalid("Invalid port: \(portStr). Must be 1-65535")
        }
    }
    
    return .valid
}
```

### Environment Name
```swift
func validateEnvironmentName(_ name: String, excluding environmentId: UUID?) -> ValidationResult {
    guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
        return .invalid("Name cannot be empty")
    }
    
    let exists = appState.environments
        .filter { $0.id != environmentId }
        .contains { $0.name.lowercased() == name.lowercased() }
    
    if exists {
        return .invalid("An environment with this name already exists")
    }
    
    return .valid
}
```

---

## UI_COMPONENTS

### MainWindow
```yaml
type: Window
title: "DEV Fwd"
style: macOS standard with traffic lights
min_size: {width: 800, height: 500}
layout: HSplitView
children:
  - Sidebar
  - DetailView
```

### Sidebar
```yaml
type: View
width: 220 (fixed)
layout: VStack
children:
  - Header:
      text: "ENVIRONMENTS"
      style: section header, muted color
  - List:
      items: appState.environments (sorted by order)
      item_view: EnvironmentRow
      selection: appState.selectedEnvironmentId
      reorderable: true
  - Spacer
  - Footer:
      button: "+ New Environment"
      action: OP_001
```

### EnvironmentRow
```yaml
type: View
layout: HStack
children:
  - Icon: folder icon
  - Text: environment.name
  - Spacer
  - Toggle:
      value: environment.isEnabled
      action: OP_005 or OP_006
  - StatusDot:
      color: computed from environment aggregate status
```

### StatusDot Colors
```swift
func environmentStatusColor(_ env: Environment) -> Color {
    guard env.isEnabled else { return .gray }
    
    let statuses = env.services.filter { $0.isEnabled }.map { $0.status }
    
    if statuses.contains(.failed) { return .red }
    if statuses.contains(.starting) || statuses.contains(.stopping) { return .yellow }
    if statuses.allSatisfy({ $0 == .running }) { return .green }
    
    return .gray
}
```

### DetailView
```yaml
type: View
layout: VStack(alignment: .leading, spacing: 16)
visible_when: appState.selectedEnvironmentId != nil
children:
  - Toolbar:
      layout: HStack
      children:
        - Button: "🗑 Delete Environment" (red, destructive)
        - Spacer
        - Button: "Save Changes"
        - Button: "+ Add Service" (primary style)
  
  - Divider
  
  - EnvironmentInfo:
      layout: Form
      fields:
        - Label: "ENV NAME"
          TextField: environment.name
          placeholder: "e.g. meera-dev, staging-2"
          disabled_when: environment.isEnabled
        
  - InterfaceList:
      header: "INTERFACES" + HelpButton(topic: "interface-variables")
      items: environment.interfaces (indexed)
      item_view: InterfaceRow
      footer: "+ Add Interface" button (disabled when environment.isEnabled)
  
  - ServiceList:
      header: "SERVICES"
      items: environment.services (sorted by order)
      item_view: ServiceRow
      empty_state: "No services. Click '+ Add Service' to add one."
```

### InterfaceRow
```yaml
type: View
layout: HStack
children:
  - Text: variableName ($IP, $IP2, etc.)
    style: monospace, muted
    width: 50
  - TextField: interface IP
    placeholder: "e.g. 127.0.0.2"
    disabled_when: environment.isEnabled
  - Spacer
  - Button: "✕" 
    visible_when: interfaces.count > 1 AND index > 0
    disabled_when: environment.isEnabled
    action: OP_003
```

### ServiceRow
```yaml
type: View
layout: VStack
style: card with border radius
children:
  - HStack:
      - StatusIndicator: service.status
      - Text: service.name (bold)
      - Spacer
      - RestartBadge (visible when restartCount > 0)
      - Toggle: service.isEnabled
      - MenuButton: "⋯"
  - HStack:
      - Icon: link/chain
      - Text: "Port: {service.ports}" (muted)
      - Spacer
      - ErrorBadge (visible when status == .failed)
```

### StatusIndicator
```yaml
type: Circle
size: 10
colors:
  stopped: gray
  starting: yellow (with pulse animation)
  running: green
  failed: red
  stopping: yellow
```

### ServiceContextMenu
```yaml
items:
  - "📋 View Logs" -> OP_008
  - "✏️ Edit" -> show edit modal
  - Divider
  - "🔄 Restart" -> stop then start service
  - "⏹ Stop" -> stop service (disabled if not running)
  - Divider
  - "🗑 Delete" -> confirm then delete
```

### AddServiceModal
```yaml
type: Sheet
title: "Add Service"
subtitle: "Configure the service parameters for your environment."
help_button: topic "writing-commands"
layout: VStack(spacing: 16)
children:
  - Field:
      label: "Service Name"
      type: TextField
      placeholder: "e.g. auth-service, payment-gateway"
      binding: newService.name
  
  - Field:
      label: "Ports"
      type: TextField
      placeholder: "e.g. 8080 or 80,443,8080"
      binding: newService.ports
  
  - Field:
      label: "Running Command"
      type: TextEditor (multiline)
      placeholder: "# Enter startup command\nkubectl port-forward --address $IP svc/name 8080:8080"
      binding: newService.command
      language_hint: "bash"
  
  - VariableHint:
      style: info box with 💡 icon
      text: dynamic based on environment.interfaces
      example: "Variables: $IP → 127.0.0.2  $IP2 → 127.0.0.3"
  
  - ButtonRow:
      - Button: "Cancel" (secondary)
      - Button: "💾 Save Service" (primary)
        disabled_when: validation fails
```

### LogViewerSheet
```yaml
type: Sheet
title: "Logs: {service.name}"
size: {width: 600, height: 400}
layout: VStack
children:
  - Header:
      HStack:
        - Text: "Logs: {service.name}"
        - Spacer
        - Button: "✕" (close)
  
  - ScrollView:
      style: monospace font, dark background
      content: ForEach service.logs
        - Text: "[{timestamp}] {message}"
          color: stderr ? .red : .primary
      behavior: always scroll to bottom on new content
  
  - Footer:
      HStack:
        - Spacer
        - Button: "📋 Copy All"
          action: copy all logs to clipboard
        - Button: "🗑 Clear"
          action: service.logs.removeAll()
```

### MenubarMenu
```yaml
type: NSMenu (AppKit)
icon: menubar icon (network/forward style)
icon_states:
  default: no environments active
  active: at least one environment running
  warning: at least one service failed
menu_items:
  - Header: "ENVIRONMENTS" (disabled, styled as section header)
  - ForEach environment in environments:
      - MenuItem:
          title: environment.name
          state: environment.isEnabled ? .on : .off
          action: toggle environment
  - Separator
  - MenuItem: "Guest Mode"
      state: appState.guestMode ? .on : .off
      action: toggle guest mode
  - Separator
  - MenuItem: "Main Frame"
      action: NSApp.activate, bring window to front
  - MenuItem: "Quit"
      action: graceful shutdown then NSApp.terminate
```

### HelpWindow
```yaml
type: Window
title: "DEV Fwd Help"
size: {width: 700, height: 500}
layout: HSplitView
children:
  - TopicSidebar:
      width: 200
      items: hierarchical topic list
      selection: currentTopic
  
  - ContentArea:
      ScrollView with formatted help text
      style: markdown-like rendering
```

### HelpTopics
```yaml
topics:
  - id: "getting-started"
    title: "Getting Started"
    children:
      - id: "what-is-devfwd"
        title: "What is DEV Fwd?"
      - id: "first-environment"
        title: "Creating Your First Environment"
      - id: "adding-services"
        title: "Adding Services"
  
  - id: "environments"
    title: "Environments"
    children:
      - id: "managing-interfaces"
        title: "Managing Interfaces"
      - id: "interface-variables"
        title: "Interface Variables ($IP, $IP2, etc.)"
      - id: "activation"
        title: "Activating/Deactivating"
  
  - id: "services"
    title: "Services"
    children:
      - id: "writing-commands"
        title: "Writing Commands"
      - id: "using-variables"
        title: "Using Variables in Commands"
      - id: "service-status"
        title: "Understanding Service Status"
      - id: "viewing-logs"
        title: "Viewing Logs"
  
  - id: "troubleshooting"
    title: "Troubleshooting"
    children:
      - id: "wont-start"
        title: "Service Won't Start"
      - id: "port-in-use"
        title: "Port Already in Use"
      - id: "permissions"
        title: "Permission Issues"
      - id: "common-errors"
        title: "Common Errors"
  
  - id: "command-examples"
    title: "Command Examples"
    children:
      - id: "kubectl-examples"
        title: "Kubernetes Port Forward"
      - id: "ssh-examples"
        title: "SSH Tunnels"
      - id: "cloudflare-examples"
        title: "Cloudflare Tunnels"
      - id: "docker-examples"
        title: "Docker Port Binding"
```

---

## GUEST_MODE

### Behavior
```yaml
activation:
  trigger: user enables Guest Mode toggle
  steps:
    1. Store list of currently active environment IDs: previouslyActive
    2. For each active environment: execute OP_006 (deactivate)
    3. Set appState.guestMode = true
  
deactivation:
  trigger: user disables Guest Mode toggle
  steps:
    1. Set appState.guestMode = false
    2. For each environment ID in previouslyActive:
       - If environment still exists: execute OP_005 (activate)
    3. Clear previouslyActive

persistence:
  - guestMode state is NOT persisted (resets to false on app launch)
  - previouslyActive is kept in memory only
```

---

## APP_LIFECYCLE

### Launch
```yaml
steps:
  1. Load config from ~/Library/Application Support/DEV Fwd/config.json
  2. If file doesn't exist: create with empty environments array
  3. Parse JSON into AppState
  4. All environments start with isEnabled = false
  5. All services start with status = .stopped
  6. Show main window
  7. Setup menubar icon and menu
```

### Quit
```yaml
trigger: user clicks Quit or Cmd+Q
steps:
  1. If any environment is active:
     a. Show confirmation: "Active environments will be stopped. Quit anyway?"
     b. If cancelled: abort quit
  2. For each active environment:
     a. Execute OP_006 (deactivate)
  3. Persist current config to disk
  4. NSApp.terminate()
```

### Persistence
```yaml
trigger: any change to environments or services
steps:
  1. Serialize appState.environments to JSON (excluding runtime state)
  2. Write to ~/Library/Application Support/DEV Fwd/config.json
  3. Handle write errors gracefully (log, don't crash)
```

---

## ERROR_HANDLING

### Error Types
```swift
enum DevFwdError: Error {
    case interfaceAlreadyInUse(ip: String)
    case interfaceUpFailed(ip: String, reason: String)
    case interfaceDownFailed(ip: String, reason: String)
    case authorizationDenied
    case authorizationFailed
    case processSpawnFailed(service: String, reason: String)
    case configLoadFailed(reason: String)
    case configSaveFailed(reason: String)
    case validationFailed(field: String, reason: String)
}
```

### Error Display
```yaml
strategy: Alert dialog for critical errors, inline for validation
critical_errors:
  - authorizationDenied: "Administrator privileges required to manage network interfaces."
  - interfaceUpFailed: "Failed to activate interface {ip}: {reason}"
  - configLoadFailed: "Failed to load configuration. Starting fresh."
  
inline_errors:
  - validation errors shown below respective fields
  - red border on invalid fields
```

---

## KEYBOARD_SHORTCUTS

```yaml
global:
  - Cmd+N: New Environment
  - Cmd+,: Open Settings
  - Cmd+?: Open Help
  
when_environment_selected:
  - Cmd+Shift+N: Add Service
  - Delete: Delete selected environment (with confirmation)
  
when_service_selected:
  - Cmd+L: View Logs
  - Delete: Delete selected service (with confirmation)
```

---

## FILE_STRUCTURE

```
DEV Fwd/
├── App/
│   ├── DEVFwdApp.swift              # @main entry point
│   └── AppDelegate.swift            # NSApplicationDelegate for menubar
├── Models/
│   ├── Environment.swift
│   ├── Service.swift
│   ├── ServiceStatus.swift
│   └── LogEntry.swift
├── ViewModels/
│   ├── AppState.swift               # Main ObservableObject
│   ├── EnvironmentViewModel.swift
│   └── ServiceViewModel.swift
├── Views/
│   ├── MainWindow/
│   │   ├── MainView.swift
│   │   ├── Sidebar.swift
│   │   ├── EnvironmentRow.swift
│   │   ├── DetailView.swift
│   │   ├── InterfaceList.swift
│   │   └── ServiceList.swift
│   ├── Components/
│   │   ├── ServiceRow.swift
│   │   ├── StatusIndicator.swift
│   │   └── InterfaceRow.swift
│   ├── Sheets/
│   │   ├── AddServiceSheet.swift
│   │   ├── EditServiceSheet.swift
│   │   └── LogViewerSheet.swift
│   ├── Menubar/
│   │   └── MenubarController.swift
│   └── Help/
│       ├── HelpWindow.swift
│       └── HelpContent.swift
├── Services/
│   ├── ProcessManager.swift         # Spawn, monitor, terminate processes
│   ├── NetworkManager.swift         # ifconfig operations
│   ├── PrivilegeManager.swift       # sudo authorization
│   ├── ConfigManager.swift          # JSON persistence
│   └── ValidationService.swift
├── Utilities/
│   ├── VariableResolver.swift       # $IP substitution
│   └── Extensions.swift
└── Resources/
    ├── Assets.xcassets
    └── Help/
        └── HelpTopics.json
```

---

## IMPLEMENTATION_PHASES

### Phase 1: MVP
```yaml
priority: 1
features:
  - [ ] Data models (Environment, Service, etc.)
  - [ ] JSON persistence (ConfigManager)
  - [ ] Main window layout (Sidebar + DetailView)
  - [ ] Environment CRUD
  - [ ] Multiple interfaces with variable naming
  - [ ] Service CRUD with Add/Edit modals
  - [ ] Input field placeholders
  - [ ] IP validation (format + uniqueness)
  - [ ] Port validation
  - [ ] Variable substitution ($IP, $IP2, etc.)
  - [ ] Environment activation (interface up + process spawn)
  - [ ] Environment deactivation (process stop + interface down)
  - [ ] Basic status indicators (stopped/starting/running/failed)
  - [ ] Simple log capture and viewing (Copy All + Clear)
  - [ ] Menubar icon with environment toggles
  - [ ] Privilege handling via osascript
```

### Phase 2: Stability
```yaml
priority: 2
features:
  - [ ] Auto-restart with exponential backoff
  - [ ] Restart counter display
  - [ ] Max restart attempts (10)
  - [ ] Service reordering (drag & drop)
  - [ ] Guest mode
  - [ ] Settings panel
  - [ ] Keyboard shortcuts
  - [ ] Help system with topic browsing
  - [ ] Contextual help buttons
```

### Phase 3: Polish
```yaml
priority: 3
features:
  - [ ] SMJobBless privileged helper (better UX than osascript)
  - [ ] Launch at login option
  - [ ] State recovery on app restart
  - [ ] Environment templates
  - [ ] Global keyboard shortcut for menubar
```

---

## COMMAND_EXAMPLES

```yaml
kubernetes_port_forward:
  description: "Forward a Kubernetes service"
  template: "kubectl port-forward --address $IP svc/{SERVICE_NAME} {LOCAL_PORT}:{REMOTE_PORT} -n {NAMESPACE}"
  example: "kubectl port-forward --address $IP svc/auth-service 8080:8080 -n development"

kubernetes_pod_forward:
  description: "Forward a specific pod"
  template: "kubectl port-forward --address $IP pod/{POD_NAME} {LOCAL_PORT}:{REMOTE_PORT}"
  example: "kubectl port-forward --address $IP pod/auth-service-abc123 8080:8080"

ssh_tunnel:
  description: "SSH tunnel to remote service"
  template: "ssh -N -L $IP:{LOCAL_PORT}:{REMOTE_HOST}:{REMOTE_PORT} {USER}@{BASTION}"
  example: "ssh -N -L $IP2:5432:database.internal:5432 admin@bastion.example.com"

cloudflare_tunnel:
  description: "Cloudflare Access TCP tunnel"
  template: "cloudflared access tcp --hostname {HOSTNAME} --url $IP:{PORT}"
  example: "cloudflared access tcp --hostname internal-api.example.com --url $IP:8080"

docker_run:
  description: "Docker container with port binding"
  template: "docker run -p $IP:{HOST_PORT}:{CONTAINER_PORT} {IMAGE}"
  example: "docker run -p $IP:3000:3000 my-service:latest"
```
