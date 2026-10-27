import Foundation

/// The folders a profile owns on disk. Claude Profiles creates them and passes their paths on;
/// it never reads, copies or shows what is inside.
public enum ProfileFolders {
    /// Folders to remove when a profile is deleted. Empty unless the user asked to delete data.
    public static func foldersToRemove(for profile: Profile, alsoDeleteData: Bool, cliRoot: URL = AppPaths.cliRoot) -> [URL] {
        guard alsoDeleteData else { return [] }
        return [profile.dataURL, AppPaths.cliConfigURL(for: profile.id, root: cliRoot)]
    }

    /// Removes the profile's folders that exist, using `remove` (the app moves them to the Trash).
    public static func removeFolders(
        for profile: Profile,
        alsoDeleteData: Bool,
        cliRoot: URL = AppPaths.cliRoot,
        using remove: (URL) throws -> Void
    ) throws {
        for url in foldersToRemove(for: profile, alsoDeleteData: alsoDeleteData, cliRoot: cliRoot)
        where FileManager.default.fileExists(atPath: url.path) {
            try remove(url)
        }
    }

    /// Creates the CLI config folder (user-only permissions) if needed.
    @discardableResult
    public static func ensureCLIConfigFolder(for id: UUID, root: URL = AppPaths.cliRoot) throws -> URL {
        let url = AppPaths.cliConfigURL(for: id, root: root)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return url
    }
}
