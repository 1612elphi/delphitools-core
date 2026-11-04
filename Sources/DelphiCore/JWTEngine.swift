import Foundation

public nonisolated enum JWTSegmentError: Sendable {
    case notBase64Url, notJSON, notAnObject

    public var label: String {
        switch self {
        case .notBase64Url: String(localized: "not base64url")
        case .notJSON: String(localized: "not JSON")
        case .notAnObject: String(localized: "not an object")
        }
    }
}

public nonisolated struct JWTJSONSegment: Sendable {
    public let byteCount: Int?
    public let members: [JSONMember]?
    public let pretty: String?
    public let error: JWTSegmentError?
}

public nonisolated struct JWTSignature: Sendable {
    public let raw: String
    public let byteCount: Int?
    public let error: JWTSegmentError?
}

public nonisolated struct JWTTimeClaim: Sendable {
    public let key: String
    public let label: String
    public let seconds: Double
    public let absolute: String
    public let isPast: Bool
}

public nonisolated struct JWTDecoded: Sendable {
    public let header: JWTJSONSegment
    public let payload: JWTJSONSegment
    public let signature: JWTSignature
    public let algorithm: String?
    public let tokenType: String?
    public let timeClaims: [JWTTimeClaim]
}

public nonisolated enum JWTResult: Sendable {
    case empty
    case segments(found: Int)
    case decoded(JWTDecoded)
}

public nonisolated enum JWTEngine {

    private static let months = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]

    // month table is gregorian
    public static func formatAbsolute(_ date: Date,
                               calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date)
        let pad = { (n: Int) in n < 10 ? "0\(n)" : String(n) }
        let month = months[(parts.month ?? 1) - 1]
        let time = [parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0]
            .map(pad).joined(separator: ":")
        return "\(pad(parts.day ?? 1)) \(month) \(parts.year ?? 0), \(time)"
    }

    public static func base64UrlToData(_ segment: String) -> Data? {
        var unpadded = segment
        while unpadded.hasSuffix("=") { unpadded.removeLast() }
        let allowed = unpadded.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
        }
        guard allowed, unpadded.count % 4 != 1 else { return nil }
        let padding = (4 - unpadded.count % 4) % 4
        let base64 = unpadded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: padding)
        return Data(base64Encoded: base64)
    }

    private static func decodeJSONSegment(_ segment: String) -> JWTJSONSegment {
        guard let data = base64UrlToData(segment) else {
            return JWTJSONSegment(byteCount: nil, members: nil, pretty: nil, error: .notBase64Url)
        }
        // lossy like TextDecoder
        guard case .success(let value) = JSONFormatEngine.parse(String(decoding: data, as: UTF8.self))
        else {
            return JWTJSONSegment(byteCount: data.count, members: nil, pretty: nil, error: .notJSON)
        }
        guard case .object(let members) = value else {
            return JWTJSONSegment(byteCount: data.count, members: nil, pretty: nil,
                                  error: .notAnObject)
        }
        return JWTJSONSegment(
            byteCount: data.count,
            members: members,
            pretty: JSONFormatEngine.format(value, indent: .two),
            error: nil
        )
    }

    private static let claimLabels: [(key: String, label: String)] = [
        ("iat", String(localized: "Issued")),
        ("nbf", String(localized: "Not before")),
        ("exp", String(localized: "Expires")),
    ]

    public static func timeClaims(in members: [JSONMember], now: Date) -> [JWTTimeClaim] {
        claimLabels.compactMap { claim in
            guard let member = members.first(where: { $0.key == claim.key }),
                  case .number(let literal) = member.value,
                  let seconds = Double(literal), seconds.isFinite else { return nil }
            let date = Date(timeIntervalSince1970: seconds)
            return JWTTimeClaim(
                key: claim.key,
                label: claim.label,
                seconds: seconds,
                absolute: formatAbsolute(date),
                isPast: date <= now
            )
        }
    }

    private static func stringClaim(_ members: [JSONMember]?, _ key: String) -> String? {
        guard let member = members?.first(where: { $0.key == key }),
              case .string(let text) = member.value else { return nil }
        return text
    }

    public static func decode(_ input: String, now: Date = Date()) -> JWTResult {
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty { return .empty }

        let segments = token.components(separatedBy: ".")
        guard segments.count == 3 else { return .segments(found: segments.count) }

        let header = decodeJSONSegment(segments[0])
        let payload = decodeJSONSegment(segments[1])
        let signatureData = base64UrlToData(segments[2])

        return .decoded(JWTDecoded(
            header: header,
            payload: payload,
            signature: JWTSignature(
                raw: segments[2],
                byteCount: signatureData?.count,
                error: signatureData == nil ? .notBase64Url : nil
            ),
            algorithm: stringClaim(header.members, "alg"),
            tokenType: stringClaim(header.members, "typ"),
            timeClaims: payload.members.map { timeClaims(in: $0, now: now) } ?? []
        ))
    }

    #if DEBUG
    public static func selfCheck() {
        // alg hs256, exp 1e9
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
            + ".eyJzdWIiOiIxIiwiZXhwIjoxMDAwMDAwMDAwfQ"
            + ".dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        guard case .decoded(let result) = decode(token) else {
            assertionFailure("valid token rejected"); return
        }
        assert(result.algorithm == "HS256")
        assert(result.tokenType == "JWT")
        assert(result.header.byteCount == 27)
        assert(result.signature.byteCount == 32)
        assert(result.timeClaims.count == 1)
        assert(result.timeClaims[0].label == String(localized: "Expires"))
        assert(result.timeClaims[0].isPast)
        assert(result.payload.pretty?.contains("\"sub\": \"1\"") == true)

        if case .segments(let found) = decode("a.b") { assert(found == 2) } else {
            assertionFailure("segment count not reported")
        }
        if case .empty = decode("   ") {} else { assertionFailure("blank token not empty") }

        guard case .decoded(let broken) = decode("!!!.!!!.!!!") else {
            assertionFailure("malformed token rejected"); return
        }
        assert(broken.header.error == .notBase64Url)

        // non-object, broken json, stray
        guard case .decoded(let odd) = decode("WzFd.ew.a") else {
            assertionFailure("odd token rejected"); return
        }
        assert(odd.header.error == .notAnObject)
        assert(odd.payload.error == .notJSON)
        assert(odd.signature.error == .notBase64Url)
        assert(base64UrlToData("ew==")?.count == 1)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        assert(formatAbsolute(Date(timeIntervalSince1970: 1_000_000_000), calendar: utc)
               == "09 Sep 2001, 01:46:40")
    }
    #endif
}
