import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Il diario: quello che Marco ha dettato, le note, e le call trascritte, in
/// una cronologia sola. Il formato e' un contratto fra il Mac e l'iPhone
/// (`docs/CONTRATTO-DIARIO.md`, fixture `prove/dati/diario/`).
///
/// Tre regole, e il perche':
///
/// - **Un file per voce, nome = id.** Due dispositivi che scrivono nella stessa
///   cartella sincronizzata non si pestano mai i piedi: nessun file e' di due.
///   Niente file indice condiviso — l'indice si ricostruisce leggendo.
/// - **Una voce scritta non si riscrive.** E' la regola delle trascrizioni
///   (AGENTS.md): una dettatura puo' finire citata, e cio' che si cita deve
///   restare quello. Scrivere su un id esistente e' un errore, non un
///   aggiornamento.
/// - **Cancellare lascia una lapide** (`<id>.cancellata.json`, senza testo):
///   senza, un secondo dispositivo che ha ancora la voce la ririporterebbe
///   in vita alla prossima sincronizzazione. Le call non si cancellano da qui:
///   la trascrizione e' evidenza e sta dove sta.
///
/// Foundation pura, e dichiarato anche per iOS: e' il pezzo che si porta
/// nell'app iPhone (`docs/PORTARE-IL-DIARIO-SU-IPHONE.md`).
public struct VoceDiario: Codable, Equatable, Sendable, Identifiable {

    public enum Tipo: String, Codable, Sendable, CaseIterable {
        case dettatura, call, nota
    }

    public enum Pulizia: String, Codable, Sendable {
        case nessuna, regole, modello
    }

    public struct Cancello: Codable, Equatable, Sendable {
        public let passato: Bool
        public let motivi: [String]
        public init(passato: Bool, motivi: [String]) { self.passato = passato; self.motivi = motivi }
    }

    public static let schemaAttuale = 1

    public let schema: Int
    public let id: UUID
    public let quando: Date
    /// «mac» o «iphone»: chi l'ha scritta.
    public let dispositivo: String
    public let tipo: Tipo
    /// Il testo inserito (dettature, note). Per le call: nil — il testo sta
    /// nella trascrizione, e non si copia.
    public let testo: String?
    /// Il testo del riconoscimento, se diverso da `testo`.
    public let testoGrezzo: String?
    public let titolo: String?
    public let pulizia: Pulizia?
    public let cancello: Cancello?
    public let motore: String?
    public let versioneOS: String?
    public let lingua: String?
    public let durataS: Double?
    /// Dove e' andata: il bundle id dell'app di destinazione.
    public let app: String?
    /// Per le call: la trascrizione, relativa alla radice dei dati
    /// (`testi/<nome>.txt`). Mai il testo.
    public let trascrizione: String?

    enum CodingKeys: String, CodingKey {
        case schema, id, quando, dispositivo, tipo, testo, titolo, pulizia, cancello, motore, lingua, app
        case testoGrezzo = "testo_grezzo"
        case versioneOS = "versione_os"
        case durataS = "durata_s"
        case trascrizione
    }

    public init(id: UUID = UUID(), quando: Date = Date(), dispositivo: String, tipo: Tipo,
                testo: String? = nil, testoGrezzo: String? = nil, titolo: String? = nil,
                pulizia: Pulizia? = nil, cancello: Cancello? = nil, motore: String? = nil,
                versioneOS: String? = nil, lingua: String? = nil, durataS: Double? = nil,
                app: String? = nil, trascrizione: String? = nil) {
        self.schema = Self.schemaAttuale
        self.id = id; self.quando = quando; self.dispositivo = dispositivo; self.tipo = tipo
        self.testo = testo
        // Il grezzo si tiene solo se dice qualcosa in piu'.
        self.testoGrezzo = testoGrezzo == testo ? nil : testoGrezzo
        self.titolo = titolo; self.pulizia = pulizia; self.cancello = cancello; self.motore = motore
        self.versioneOS = versioneOS; self.lingua = lingua; self.durataS = durataS; self.app = app
        self.trascrizione = trascrizione
    }

    /// Una call vista dal diario: l'id si ricava dal percorso della
    /// trascrizione, cosi' la stessa call ha lo stesso id su ogni dispositivo
    /// e a ogni lettura (niente doppioni).
    public static func call(trascrizione relativa: String, titolo: String, quando: Date,
                            durataS: Double? = nil) -> VoceDiario {
        VoceDiario(id: idStabile("call:" + relativa), quando: quando, dispositivo: "mac", tipo: .call,
                   titolo: titolo, durataS: durataS, trascrizione: relativa)
    }

    /// Un UUID deterministico da un testo (FNV-1a a 128 bit, versione 8):
    /// Foundation non ha SHA senza CryptoKit, e qui non serve una firma — serve
    /// che lo stesso percorso dia lo stesso id su Mac e iPhone.
    static func idStabile(_ s: String) -> UUID {
        var a: UInt64 = 0xcbf2_9ce4_8422_2325, b: UInt64 = 0x8422_2325_cbf2_9ce4
        for byte in s.utf8 {
            a = (a ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            b = (b ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 &+ a
        }
        var byte = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { byte[i] = UInt8((a >> (8 * i)) & 0xff); byte[8 + i] = UInt8((b >> (8 * i)) & 0xff) }
        byte[6] = (byte[6] & 0x0f) | 0x80  // versione 8: «definito dall'applicazione»
        byte[8] = (byte[8] & 0x3f) | 0x80  // variante RFC 4122
        return UUID(uuid: (byte[0], byte[1], byte[2], byte[3], byte[4], byte[5], byte[6], byte[7],
                           byte[8], byte[9], byte[10], byte[11], byte[12], byte[13], byte[14], byte[15]))
    }
}

/// La lapide di una voce cancellata: chi, quando, e nient'altro.
public struct Lapide: Codable, Equatable, Sendable {
    public let schema: Int
    public let id: UUID
    public let cancellataIl: Date
    public let dispositivo: String
    enum CodingKeys: String, CodingKey {
        case schema, id, dispositivo
        case cancellataIl = "cancellata_il"
    }
    public init(id: UUID, cancellataIl: Date = Date(), dispositivo: String) {
        self.schema = VoceDiario.schemaAttuale; self.id = id
        self.cancellataIl = cancellataIl; self.dispositivo = dispositivo
    }
}

/// Una cartella di voci. Tutte le operazioni passano da qui.
public final class Diario: @unchecked Sendable {

    public enum Errore: Error, CustomStringConvertible, Equatable {
        case esisteGia(UUID)
        case nonSiCancella(VoceDiario.Tipo)
        case nonTrovata(UUID)
        public var description: String {
            switch self {
            case .esisteGia(let id): "la voce \(id) esiste gia': una voce scritta non si riscrive"
            case .nonSiCancella(let t): "le voci di tipo \(t.rawValue) non si cancellano dal diario"
            case .nonTrovata(let id): "la voce \(id) non c'e'"
            }
        }
    }

    public let cartella: URL
    public let dispositivo: String

    public init(cartella: URL, dispositivo: String) {
        self.cartella = cartella
        self.dispositivo = dispositivo
    }

    // MARK: - Il formato su disco (il contratto)

    public static func codificatore() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .custom { data, cod in
            var c = cod.singleValueContainer()
            try c.encode(Self.iso(data))
        }
        return e
    }

    public static func decodificatore() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            guard let data = Self.leggiISO(s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath,
                                                        debugDescription: "data non ISO 8601: \(s)"))
            }
            return data
        }
        return d
    }

    /// ISO 8601 **con il fuso** (`2026-09-29T21:30:05+02:00`): una dettatura
    /// fatta in viaggio deve dire l'ora che era li'.
    static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f.string(from: d)
    }

    static func leggiISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    public func file(_ id: UUID) -> URL { cartella.appendingPathComponent("\(id.uuidString.lowercased()).json") }
    func lapide(_ id: UUID) -> URL {
        cartella.appendingPathComponent("\(id.uuidString.lowercased()).cancellata.json")
    }

    // MARK: - Scrivere

    /// Scrive una voce nuova. Atomico (o c'e' tutta o non c'e') ed esclusivo:
    /// se l'id esiste gia' — o e' stato cancellato — e' un errore.
    public func scrivi(_ v: VoceDiario) throws {
        try FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: lapide(v.id).path) { throw Errore.esisteGia(v.id) }
        try scriviEsclusivo(try Self.codificatore().encode(v), in: file(v.id), id: v.id)
    }

    /// Cancella una dettatura o una nota: prima la lapide, poi il file. Se il
    /// secondo passo non riesce, la lapide basta a nasconderla ovunque.
    public func cancella(_ id: UUID) throws {
        guard let v = try leggi(file(id)) else { throw Errore.nonTrovata(id) }
        guard v.tipo != .call else { throw Errore.nonSiCancella(.call) }
        let l = Lapide(id: id, dispositivo: dispositivo)
        if !FileManager.default.fileExists(atPath: lapide(id).path) {
            try scriviEsclusivo(try Self.codificatore().encode(l), in: lapide(id), id: id)
        }
        #if os(Linux)
        try FileManager.default.removeItem(at: file(id))
        #else
        try coordinato(file(id), scrittura: true, opzioni: .forDeleting) { try FileManager.default.removeItem(at: $0) }
        #endif
    }

    /// Scrittura in un file temporaneo nella stessa cartella, poi
    /// `renamex_np(RENAME_EXCL)`: atomica **e** senza sovrascrivere, cosa che
    /// `Data.write` non sa fare insieme (`.atomic` e `.withoutOverwriting`
    /// si escludono).
    func scriviEsclusivo(_ dati: Data, in destinazione: URL, id: UUID) throws {
        #if os(Linux)
        let fd = destinazione.path.withCString { open($0, O_WRONLY | O_CREAT | O_EXCL, 0o600) }
        if fd < 0 {
            if errno == EEXIST { throw Errore.esisteGia(id) }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try handle.write(contentsOf: dati)
        try handle.close()
        #else
        let temporaneo = cartella.appendingPathComponent(".\(UUID().uuidString).tmp")
        try dati.write(to: temporaneo)
        defer { try? FileManager.default.removeItem(at: temporaneo) }
        try coordinato(destinazione, scrittura: true) { dove in
            if renamex_np(temporaneo.path, dove.path, UInt32(RENAME_EXCL)) != 0 {
                if errno == EEXIST { throw Errore.esisteGia(id) }
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        }
        #endif
    }

    /// `NSFileCoordinator`: in una cartella di iCloud Drive e' il modo di dire
    /// al sistema «sto scrivendo io», e di non leggere a meta' un file che
    /// sta arrivando dall'altro dispositivo.
    #if os(Linux)
    func coordinato(_ url: URL, scrittura: Bool, _ corpo: (URL) throws -> Void) throws {
        try corpo(url)
    }
    #else
    func coordinato(_ url: URL, scrittura: Bool, opzioni: NSFileCoordinator.WritingOptions = [],
                    _ corpo: (URL) throws -> Void) throws {
        var errore: NSError?
        var interno: Error?
        let c = NSFileCoordinator(filePresenter: nil)
        if scrittura {
            c.coordinate(writingItemAt: url, options: opzioni, error: &errore) { u in
                do { try corpo(u) } catch { interno = error }
            }
        } else {
            c.coordinate(readingItemAt: url, options: [], error: &errore) { u in
                do { try corpo(u) } catch { interno = error }
            }
        }
        if let interno { throw interno }
        if let errore { throw errore }
    }
    #endif

    // MARK: - Leggere

    func leggi(_ url: URL) throws -> VoceDiario? {
        var dati: Data?
        try coordinato(url, scrittura: false) { dati = try? Data(contentsOf: $0) }
        guard let dati else { return nil }
        return try? Self.decodificatore().decode(VoceDiario.self, from: dati)
    }

    /// Tutte le voci vive, dalla piu' recente. Le lapidi nascondono le voci
    /// cancellate (anche quelle arrivate dopo da un altro dispositivo); un file
    /// illeggibile si salta senza far cadere il resto.
    public func voci() -> [VoceDiario] {
        let nomi = (try? FileManager.default.contentsOfDirectory(atPath: cartella.path)) ?? []
        let morte = Set(nomi.filter { $0.hasSuffix(".cancellata.json") }
            .map { String($0.dropLast(".cancellata.json".count)) })
        return nomi
            .filter { $0.hasSuffix(".json") && !$0.hasSuffix(".cancellata.json") && !$0.hasPrefix(".") }
            .filter { !morte.contains(String($0.dropLast(".json".count))) }
            .compactMap { try? leggi(cartella.appendingPathComponent($0)) }
            .sorted { $0.quando > $1.quando }
    }

    /// Ricerca senza maiuscole ne' accenti su testo, grezzo e titolo.
    public static func cerca(_ q: String, in voci: [VoceDiario], tipo: VoceDiario.Tipo? = nil) -> [VoceDiario] {
        let q = q.trimmingCharacters(in: .whitespacesAndNewlines)
        return voci.filter { v in
            guard tipo == nil || v.tipo == tipo else { return false }
            guard !q.isEmpty else { return true }
            return [v.testo, v.testoGrezzo, v.titolo].compactMap { $0 }.contains {
                $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }
}
