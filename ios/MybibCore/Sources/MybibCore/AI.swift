import Foundation

/// Recognise items on a shelf photo (or a single cover) with Claude's vision.
/// The API key is the user's own, stored only on this device and sent only to api.anthropic.com.

public struct Recognized: Equatable, Sendable {
    public let kind: String, title: String, series: String, volume: String, publisher: String, language: String, confidence: String, remark: String
    public let creators: [String]

    public init(json j: JSONObject) {
        let k = j["kind"] as? String ?? ""
        kind = kinds.contains(k) ? k : "book"
        title = (j["title"] as? String ?? "").trimmed
        creators = ((j["creators"] as? [Any]) ?? []).compactMap { ($0 as? String)?.trimmed.nonEmpty }
        series = j["series"] as? String ?? ""
        volume = j["volume"] as? String ?? ""
        publisher = j["publisher"] as? String ?? ""
        language = j["language"] as? String ?? ""
        confidence = j["confidence"] as? String ?? "high"
        remark = j["remark"] as? String ?? ""
    }

    /// Item draft for normalizeItem / the form.
    public func toDraft() -> JSONObject {
        var d: JSONObject = ["kind": kind, "title": title, "creators": creators, "source": "ai"]
        if !series.isEmpty { d["series"] = series }
        if !volume.isEmpty { d["volume"] = volume }
        if !publisher.isEmpty { d["publisher"] = publisher }
        if !language.isEmpty { d["language"] = language }
        if confidence != "high" { d["needsCheck"] = true }
        return d
    }
}

public struct RecognizeError: LocalizedError, Equatable {
    /// auth, refusal, rate, network, parse, other
    public let code: String
    public let message: String

    public init(_ code: String, _ message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? { message }
}

private func schema() -> JSONObject {
    let str: JSONObject = ["type": "string"]
    let props: JSONObject = [
        "kind": ["type": "string", "enum": kinds] as JSONObject,
        "title": str,
        "creators": ["type": "array", "items": str] as JSONObject,
        "series": str,
        "volume": str,
        "publisher": str,
        "language": str,
        "confidence": ["type": "string", "enum": ["high", "medium", "low"]] as JSONObject,
        "remark": str,
    ]
    let item: JSONObject = [
        "type": "object",
        "additionalProperties": false,
        "required": ["kind", "title", "creators", "series", "volume", "publisher", "language", "confidence", "remark"],
        "properties": props,
    ]
    let items: JSONObject = ["type": "array", "items": item]
    return ["type": "object", "additionalProperties": false, "required": ["items"], "properties": ["items": items] as JSONObject]
}

private let prompt = """
This photo shows part of a private home library: book spines (often vertical, sometimes upside down or lying flat), maybe also front covers, board game boxes, DVDs or CDs.

List every item whose spine or cover you can see, from left to right and top to bottom. For each item:
- kind: "book" (including comics, picture books, magazines-with-ISBN), "game" (board/card games), "dvd" (DVD/Blu-ray) or "cd" (music CDs, audio-book CDs count as "cd").
- title: exactly as printed, in the original script (keep Chinese characters as characters, German umlauts, etc.). Use the book's real title, not the series name, when both are visible.
- creators: authors / artists / directors / designers as printed (empty array if none visible). If you are confident who the author is from the title alone (a well-known book), you may add them and say so in remark.
- series and volume: e.g. "Asterix" / "36", "bpb Schriftenreihe" / "11128", Chinese multi-volume sets "金瓶梅词话" / "1".
- publisher: if visible on the spine (Reclam, dtv, Carlsen, Ravensburger, btb, Hanser …), else "".
- language: ISO 639-1 code of the item's language ("de", "en", "zh", "tr", "la", "fr" …), "" if unclear.
- confidence: "high" if clearly readable, "medium" if partly guessed, "low" if mostly guessed.
- remark: short note on what was unclear, else "".

Skip things that are not catalogue items (folders, loose papers, boxes of toys, stacks of newspapers, notebooks without a title). Do not invent items you cannot see. If a spine is too blurry to read at all, skip it rather than guessing wildly.
"""

public struct Claude: Sendable {
    public var http: any HTTPClient

    public init(http: any HTTPClient = URLSessionHTTP()) {
        self.http = http
    }

    /// The Messages API request for one photo (structured output, server-side model fallback).
    public func request(apiKey: String, model: String, jpeg: Data, hint: String = "") throws -> URLRequest {
        let h = hint.trimmed
        let text = prompt + (h.isEmpty ? "" : "\n\nHint from the owner: \(h)")
        let image: JSONObject = [
            "type": "image",
            "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()] as JSONObject,
        ]
        let content: [JSONObject] = [image, ["type": "text", "text": text]]
        let message: JSONObject = ["role": "user", "content": content]
        let format: JSONObject = ["type": "json_schema", "schema": schema()]
        let body: JSONObject = [
            "model": model,
            "max_tokens": 16000,
            "fallbacks": "default",
            "output_config": ["effort": "medium", "format": format] as JSONObject,
            "messages": [message],
        ]
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { throw RecognizeError("other", "bad URL") }
        var req = URLRequest(url: url, timeoutInterval: 300)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try encodeJSON(body)
        return req
    }

    public func recognizePhoto(apiKey: String, model: String, jpeg: Data, hint: String = "") async throws -> [Recognized] {
        let req = try request(apiKey: apiKey, model: model, jpeg: jpeg, hint: hint)
        let reply: (Data, HTTPURLResponse)
        do {
            reply = try await http.send(req)
        } catch {
            throw RecognizeError("network", error.localizedDescription)
        }
        let (data, res) = reply
        let text = String(decoding: data, as: UTF8.self)
        if res.statusCode == 401 || res.statusCode == 403 { throw RecognizeError("auth", text) }
        if res.statusCode == 429 || res.statusCode == 529 { throw RecognizeError("rate", text) }
        if res.statusCode != 200 { throw RecognizeError("other", "HTTP \(res.statusCode)") }
        guard let msg = (try? decodeJSON(data)) as? JSONObject else { throw RecognizeError("parse", "unexpected answer") }
        let stop = msg["stop_reason"] as? String
        if stop == "refusal" {
            throw RecognizeError("refusal", (msg["stop_details"] as? JSONObject)?["explanation"] as? String ?? "refused")
        }
        var out = ""
        for case let b as JSONObject in (msg["content"] as? [Any]) ?? [] where (b["type"] as? String) == "text" {
            out += b["text"] as? String ?? ""
        }
        guard let parsed = (try? decodeJSON(Data(out.utf8))) as? JSONObject, let list = parsed["items"] as? [Any] else {
            throw RecognizeError("parse", stop == "max_tokens" ? "too many items in one photo – try a closer photo" : "unexpected answer")
        }
        return list.compactMap { $0 as? JSONObject }.map { Recognized(json: $0) }.filter { !$0.title.isEmpty }
    }
}
