import Foundation

enum ProtocolMapper {
    static func skill(_ wire: SkillWireMetadata, errors: [SkillWireError]) -> SkillRecord {
        SkillRecord(
            name: wire.name,
            displayName: DiagnosticRedactor.sanitize(wire.interface?.displayName ?? wire.name),
            description: DiagnosticRedactor.sanitize(wire.description),
            shortDescription: (wire.interface?.shortDescription ?? wire.shortDescription).map(DiagnosticRedactor.sanitize),
            path: wire.path,
            scope: SkillScope(protocolValue: wire.scope),
            rawScope: DiagnosticRedactor.sanitize(wire.scope),
            isEnabled: wire.enabled,
            invocationPolicy: SkillMetadataResolver.invocationPolicy(skillPath: wire.path),
            dependencies: wire.dependencies?.tools.map(dependency) ?? [],
            errors: errors
                .filter { $0.path == wire.path || wire.path.hasPrefix($0.path) }
                .map { DiagnosticRedactor.sanitize($0.message) }
        )
    }

    static func hook(_ wire: HookWireMetadata) -> HookRecord {
        HookRecord(
            key: wire.key,
            event: HookEvent(protocolValue: wire.eventName),
            rawEventName: DiagnosticRedactor.sanitize(wire.eventName),
            handlerType: HookHandlerType(protocolValue: wire.handlerType),
            rawHandlerType: DiagnosticRedactor.sanitize(wire.handlerType),
            matcher: wire.matcher.map(DiagnosticRedactor.sanitize),
            command: wire.command.map(DiagnosticRedactor.sanitize),
            timeoutSeconds: wire.timeoutSec,
            statusMessage: wire.statusMessage.map(DiagnosticRedactor.sanitize),
            sourcePath: wire.sourcePath,
            source: HookSource(protocolValue: wire.source),
            rawSource: DiagnosticRedactor.sanitize(wire.source),
            pluginID: wire.pluginId.map(DiagnosticRedactor.sanitize),
            displayOrder: wire.displayOrder,
            isEnabled: wire.enabled,
            isManaged: wire.isManaged,
            currentHash: wire.currentHash,
            trustStatus: HookTrustStatus(protocolValue: wire.trustStatus),
            rawTrustStatus: DiagnosticRedactor.sanitize(wire.trustStatus)
        )
    }

    private static func dependency(_ wire: SkillWireToolDependency) -> SkillDependency {
        let availability: DependencyAvailability
        if wire.type == "env_var" {
            availability = ProcessInfo.processInfo.environment[wire.value] == nil ? .missing : .available
        } else {
            availability = .unknown
        }
        return SkillDependency(
            type: wire.type,
            value: DiagnosticRedactor.dependencyValue(type: wire.type, value: wire.value),
            summary: wire.description.map(DiagnosticRedactor.sanitize),
            availability: availability
        )
    }
}
