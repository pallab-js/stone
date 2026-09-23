import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct DatabaseBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.database] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}