import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum DocumentExport {
    @MainActor
    static func pdfData<Content: View>(
        root content: Content,
        pageSize: CGSize = CGSize(width: 595, height: 842)
    ) -> Data? {
        let hosting = NSHostingView(rootView: content)
        let fitted = hosting.fittingSize
        let width = max(pageSize.width, ceil(fitted.width))
        let height = max(pageSize.height, ceil(fitted.height) + 4)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
        let data = hosting.dataWithPDF(inside: hosting.bounds)
        return data
    }

    static func save(_ data: Data, suggestedName: String, fileType: UTType) {
        guard data.count > 0 else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [fileType]
        panel.nameFieldStringValue = suggestedName
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    static func saveCSV(_ content: String, suggestedName: String) {
        let data = Data(content.utf8)
        save(data, suggestedName: suggestedName, fileType: .commaSeparatedText)
    }
}

enum CSVWriter {
    static func string(headers: [String], rows: [[String]]) -> String {
        var lines: [String] = []
        if headers.isNotEmpty {
            lines.append(headers.map(escape).joined(separator: ","))
        }
        for row in rows {
            lines.append(row.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }
}

private extension Array {
    var isNotEmpty: Bool { !isEmpty }
}