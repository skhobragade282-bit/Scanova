import Foundation
import PDFKit

struct FileStorageService {
    func save(documentData: Data, named fileName: String, directory: URL? = nil) throws -> URL {
        let baseDirectory = directory ?? documentsDirectory()
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let destination = baseDirectory.appendingPathComponent(sanitizedFileName(fileName)).appendingPathExtension("pdf")
        try documentData.write(to: destination, options: .atomic)
        return destination
    }

    func save(images: [Data], named fileName: String, directory: URL? = nil) throws -> [URL] {
        let baseDirectory = directory ?? documentsDirectory().appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        let sanitizedBaseName = sanitizedFileName(fileName)
        return try images.enumerated().map { index, imageData in
            let destination = baseDirectory
                .appendingPathComponent("\(sanitizedBaseName)-page-\(index + 1)")
                .appendingPathExtension("png")
            try imageData.write(to: destination, options: .atomic)
            return destination
        }
    }

    func listRecentDocuments() -> [RecentDocumentItem] {
        let directory = documentsDirectory()
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey]
        let fileURLs = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []

        let metadata = storedMetadataByPath()
        var activePaths = Set<String>()

        let pdfURLs = fileURLs.filter { $0.pathExtension.lowercased() == "pdf" }
        var items: [RecentDocumentItem] = []

        for url in pdfURLs {
            guard let resourceValues = try? url.resourceValues(forKeys: Set(keys)),
                  resourceValues.isRegularFile == true else {
                continue
            }

            let pageCount = PDFDocument(url: url)?.pageCount ?? 0
            let storedRecord = metadata[url.path]
            let name = storedRecord?.name ?? url.deletingPathExtension().lastPathComponent
            let modifiedAt = resourceValues.contentModificationDate ?? .distantPast
            let documentType = storedRecord?.documentType ?? .general
            let fileSizeBytes = resourceValues.fileSize ?? 0
            activePaths.insert(url.path)

            items.append(
                RecentDocumentItem(
                    id: UUID(),
                    name: name,
                    modifiedAt: modifiedAt,
                    documentType: documentType,
                    pageCount: pageCount,
                    fileSizeBytes: fileSizeBytes,
                    fileURL: url
                )
            )
        }

        items.sort { $0.modifiedAt > $1.modifiedAt }

        cleanupMetadata(removingMissingPathsExcept: activePaths)
        return items
    }

    func deleteDocument(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
        removeMetadata(for: url)
    }

    func upsertDocumentMetadata(
        for url: URL,
        name: String,
        documentType: DocumentType,
        pageCount: Int,
        modifiedAt: Date = Date()
    ) {
        var allMetadata = loadStoredMetadata()
        let record = StoredDocumentRecord(
            filePath: url.path,
            name: name,
            documentType: documentType,
            pageCount: pageCount,
            modifiedAt: modifiedAt
        )

        if let index = allMetadata.firstIndex(where: { $0.filePath == url.path }) {
            allMetadata[index] = record
        } else {
            allMetadata.append(record)
        }

        saveStoredMetadata(allMetadata)
    }

    private func documentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    private func sanitizedFileName(_ fileName: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let components = fileName.components(separatedBy: invalidCharacters)
        let sanitized = components.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Scanova-Document" : sanitized
    }

    private func metadataFileURL() -> URL {
        documentsDirectory().appendingPathComponent(".scanova-library").appendingPathExtension("json")
    }

    private func loadStoredMetadata() -> [StoredDocumentRecord] {
        let url = metadataFileURL()
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([StoredDocumentRecord].self, from: data)) ?? []
    }

    private func saveStoredMetadata(_ records: [StoredDocumentRecord]) {
        let url = metadataFileURL()
        let sorted = records.sorted { $0.modifiedAt > $1.modifiedAt }
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        try? FileManager.default.createDirectory(at: documentsDirectory(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func removeMetadata(for url: URL) {
        let filtered = loadStoredMetadata().filter { $0.filePath != url.path }
        saveStoredMetadata(filtered)
    }

    private func storedMetadataByPath() -> [String: StoredDocumentRecord] {
        Dictionary(uniqueKeysWithValues: loadStoredMetadata().map { ($0.filePath, $0) })
    }

    private func cleanupMetadata(removingMissingPathsExcept activePaths: Set<String>) {
        let filtered = loadStoredMetadata().filter { activePaths.contains($0.filePath) }
        saveStoredMetadata(filtered)
    }
}
