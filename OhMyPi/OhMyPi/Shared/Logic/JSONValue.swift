//
//  JSONValue.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import Foundation

/// Dynamic JSON tree used for RPC payloads whose shape is open-ended
/// (tool arguments, tool results, extension widgets).
nonisolated enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: - Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let bool):
            try container.encode(bool)
        case .number(let number):
            try container.encode(number)
        case .string(let string):
            try container.encode(string)
        case .array(let array):
            try container.encode(array)
        case .object(let object):
            try container.encode(object)
        }
    }

    // MARK: - Accessors

    subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    subscript(index: Int) -> JSONValue? {
        guard case .array(let array) = self, array.indices.contains(index) else {
            return nil
        }
        return array[index]
    }

    var stringValue: String? {
        guard case .string(let string) = self else { return nil }
        return string
    }

    var doubleValue: Double? {
        guard case .number(let number) = self else { return nil }
        return number
    }

    var intValue: Int? {
        doubleValue.map(Int.init)
    }

    var boolValue: Bool? {
        guard case .bool(let bool) = self else { return nil }
        return bool
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let array) = self else { return nil }
        return array
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let object) = self else { return nil }
        return object
    }

    var isNull: Bool {
        if case .null = self { true } else { false }
    }

    // MARK: - Conversion

    /// Re-decodes this value into a concrete `Decodable` type.
    func decoded<Value: Decodable>(as type: Value.Type = Value.self) throws -> Value {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(Value.self, from: data)
    }

    /// Pretty printed JSON, used for tool arguments and raw payload inspection.
    var prettyPrinted: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        guard
            let data = try? encoder.encode(self),
            let string = String(data: data, encoding: .utf8)
        else {
            return ""
        }

        return string
    }
}

// MARK: - Literals

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByNilLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
    nonisolated init(stringLiteral value: String) {
        self = .string(value)
    }

    nonisolated init(booleanLiteral value: Bool) {
        self = .bool(value)
    }

    nonisolated init(integerLiteral value: Int) {
        self = .number(Double(value))
    }

    nonisolated init(floatLiteral value: Double) {
        self = .number(value)
    }

    nonisolated init(nilLiteral: ()) {
        self = .null
    }

    nonisolated init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }

    nonisolated init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
