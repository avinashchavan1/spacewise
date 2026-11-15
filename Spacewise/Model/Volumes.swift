import Foundation

struct VolumeInfo: Identifiable, Hashable {
    let url: URL
    let name: String
    let total: Int64
    let available: Int64
    let isInternal: Bool
    let isEjectable: Bool
    let format: String

    var id: URL { url }
    var used: Int64 { max(0, total - available) }
    var usedFraction: Double { total > 0 ? min(1, Double(used) / Double(total)) : 0 }
    var isStartupDisk: Bool { url.path == "/" }

    var symbol: String {
        if isStartupDisk || isInternal { return "internaldrive" }
        return "externaldrive"
    }

    static func loadAll() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey,
            .volumeIsEjectableKey, .volumeLocalizedFormatDescriptionKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        var volumes: [VolumeInfo] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let total = Int64(values.volumeTotalCapacity ?? 0)
            guard total > 0 else { continue }
            // "Important usage" includes space macOS can purge on demand, which
            // matches what the Finder reports as available.
            var available = values.volumeAvailableCapacityForImportantUsage ?? 0
            if available <= 0 { available = Int64(values.volumeAvailableCapacity ?? 0) }
            volumes.append(VolumeInfo(
                url: url,
                name: values.volumeName ?? url.lastPathComponent,
                total: total,
                available: min(available, total),
                isInternal: values.volumeIsInternal ?? false,
                isEjectable: values.volumeIsEjectable ?? false,
                format: values.volumeLocalizedFormatDescription ?? ""
            ))
        }
        return volumes.sorted { lhs, rhs in
            if lhs.isStartupDisk != rhs.isStartupDisk { return lhs.isStartupDisk }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
