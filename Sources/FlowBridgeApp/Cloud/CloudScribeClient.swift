import FlowBridgeShared
import Foundation

/// Minimal ElevenLabs Scribe v2 batch client: one multipart POST through
/// the CloudGate, the personal vocabulary as `keyterms`, one retry, and no
/// sensitive content in the logs (never the key, never the text).
enum CloudScribeClient {
    struct Result {
        let text: String
        let languageCode: String?
    }

    enum ClientError: Error, LocalizedError {
        case missingKey
        case badStatus(Int)
        case emptyText

        var errorDescription: String? {
            switch self {
            case .missingKey: return "No ElevenLabs API key saved."
            case .badStatus(let code): return "ElevenLabs returned status \(code)."
            case .emptyText: return "ElevenLabs returned an empty transcript."
            }
        }
    }

    private static let endpoint = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!

    static func transcribe(fileURL: URL, language: DictationLanguage) async throws -> Result {
        do {
            return try await attempt(fileURL: fileURL, language: language)
        } catch {
            // One retry: transient network blips are common on cellular.
            FBLog.log("cloud batch: first attempt failed (\(error)), retrying")
            return try await attempt(fileURL: fileURL, language: language)
        }
    }

    private static func attempt(fileURL: URL, language: DictationLanguage) async throws -> Result {
        guard let apiKey = CloudCredentialsStore.load() else {
            throw ClientError.missingKey
        }

        let audio = try Data(contentsOf: fileURL)
        let boundary = "flowbridge-\(UUID().uuidString)"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendField(named: "model_id", value: "scribe_v2", boundary: boundary)
        if let code = language.whisperCode {
            body.appendField(named: "language_code", value: code, boundary: boundary)
        }
        for term in (try? VocabularyStore())?.terms() ?? [] {
            body.appendField(named: "keyterms", value: term, boundary: boundary)
        }
        body.appendFile(named: "file", filename: "dictation.wav", contentType: "audio/wav", data: audio, boundary: boundary)
        body.appendClosing(boundary: boundary)
        request.httpBody = body

        CloudGate.noteRequest(host: endpoint.host ?? "api.elevenlabs.io")
        let started = Date()
        let (data, response) = try await CloudGate.session().data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        FBLog.log("cloud batch: status \(status), \(audio.count / 1024)KB up, \(data.count)B down, \(Int(Date().timeIntervalSince(started)))s")

        guard (200..<300).contains(status) else {
            throw ClientError.badStatus(status)
        }

        struct Payload: Decodable {
            let text: String
            let languageCode: String?

            enum CodingKeys: String, CodingKey {
                case text
                case languageCode = "language_code"
            }
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let text = DictationTextNormalizer.normalize(payload.text)
        guard !text.isEmpty else {
            throw ClientError.emptyText
        }
        return Result(text: text, languageCode: payload.languageCode)
    }
}

private extension Data {
    mutating func appendField(named name: String, value: String, boundary: String) {
        append(utf8: "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
    }

    mutating func appendFile(named name: String, filename: String, contentType: String, data: Data, boundary: String) {
        append(utf8: "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(contentType)\r\n\r\n")
        append(data)
        append(utf8: "\r\n")
    }

    mutating func appendClosing(boundary: String) {
        append(utf8: "--\(boundary)--\r\n")
    }

    mutating func append(utf8 string: String) {
        append(Data(string.utf8))
    }
}
