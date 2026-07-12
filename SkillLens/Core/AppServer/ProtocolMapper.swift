import Foundation

enum ProtocolMapper {
    static func skill(_ wire: SkillWireMetadata, errors: [SkillWireError]) -> SkillRecord {
        SkillRecord(
            name: wire.name,
            displayName: wire.interface?.displayName ?? wire.name,
            description: wire.description,
            shortDescription: wire.interface?.shortDescription ?? wire.shortDescription,
            path: wire.path,
            scope: SkillScope(protocolValue: wire.scope),
            rawScope: wire.scope,
            isEnabled: wire.enabled,
            invocationPolicy: SkillMetadataResolver.invocationPolicy(skillPath: wire.path),
            dependencies: wire.dependencies?.tools.map(dependency) ?? [],
            errors: errors
                .filter { $0.path == wire.path || wire.path.hasPrefix($0.path) }
                .map(\.message)
        )
    }

    static func hook(_ wire: HookWireMetadata) -> HookRecord {
        HookRecord(
            key: wire.key,
            event: HookEvent(protocolValue: wire.eventName),
            rawEventName: wire.eventName,
            handlerType: HookHandlerType(protocolValue: wire.handlerType),
            rawHandlerType: wire.handlerType,
            matcher: wire.matcher,
            command: wire.command,
            timeoutSeconds: wire.timeoutSec,
            statusMessage: wire.statusMessage,
            sourcePath: wire.sourcePath,
            source: HookSource(protocolValue: wire.source),
            rawSource: wire.source,
            pluginID: wire.pluginId,
            displayOrder: wire.displayOrder,
            isEnabled: wire.enabled,
            isManaged: wire.isManaged,
            currentHash: wire.currentHash,
            trustStatus: HookTrustStatus(protocolValue: wire.trustStatus),
            rawTrustStatus: wire.trustStatus
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
            value: wire.value,
            summary: wire.description,
            availability: availability
        )
    }
}
