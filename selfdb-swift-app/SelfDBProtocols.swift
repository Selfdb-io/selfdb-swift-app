//
//  SelfDBProtocols.swift
//  selfdb-swift-app
//
//  Protocol-based architecture for SelfDB operations
//

import Foundation
import SelfDB

// MARK: - Core Protocol for SelfDB Storable Models

protocol SelfDBStorable: Codable, Identifiable, Equatable {
    var id: String? { get set }
    static var tableName: String { get }
    
    // Convert from database row to model
    static func fromRow(_ row: [String: AnyCodable]) -> Self?
    
    // Convert to database row for insert/update
    func toRow() -> [String: Any]
}

// MARK: - Protocol for Models with File Attachments

protocol SelfDBFileAttachable: SelfDBStorable {
    var fileId: String? { get set }
}

// MARK: - Protocol Extensions

extension SelfDBStorable {
    // Default implementation for models without special conversion needs
    static func fromRow(_ row: [String: AnyCodable]) -> Self? {
        // Convert AnyCodable dictionary to Data for decoding
        guard let jsonData = try? JSONSerialization.data(withJSONObject: row.mapValues { $0.value }) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        return try? decoder.decode(Self.self, from: jsonData)
    }
    
    func toRow() -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        
        guard let jsonData = try? encoder.encode(self),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return [:]
        }
        
        // Remove nil values, empty strings, and timestamp fields (let DB handle them)
        return dict.compactMapValues { value in
            if let stringValue = value as? String, stringValue.isEmpty {
                return nil
            }
            return value
        }.filter { key, _ in
            // Exclude timestamp fields - let the database handle them
            !["created_at", "updated_at", "id"].contains(key)
        }
    }
}

extension SelfDBFileAttachable {
    var hasFile: Bool {
        guard let fileId = fileId,
              !fileId.isEmpty,
              fileId != "null",
              fileId != "nil" else {
            return false
        }
        return true
    }
}