//
//  SelfDBContext.swift
//  selfdb-swift-app
//
//  Generic CRUD context for SelfDB operations
//

import Foundation
import SelfDB

@MainActor
struct SelfDBContext<T: SelfDBStorable> {
    
    // MARK: - Create
    
    @discardableResult
    static func create(_ model: T, manager: SelfDBManager, fileData: Data? = nil, filename: String? = nil) async -> T? {
        guard let sdk = manager.selfDB else { return nil }
        
        // Build the row data manually to avoid encoding issues
        var rowData: [String: Any] = [:]
        
        // For now, fall back to the model's toRow method but exclude problematic fields
        let modelData = model.toRow()
        for (key, value) in modelData {
            rowData[key] = value
        }
        
        // Handle file upload if model supports it and data is provided
        if let data = fileData, let name = filename {
            // Ensure bucket exists
            if manager.bucketId == nil {
                await manager.ensureUserBucket()
            }
            
            if let bucket = manager.bucketId,
               let fileId = await manager.uploadFile(data: data, filename: name, bucketId: bucket) {
                rowData["file_id"] = fileId
            }
        }
        
        // Add user_id if authenticated
        if let uid = manager.currentUser?.id, !uid.isEmpty {
            rowData["user_id"] = uid
        }
        
        let res = await sdk.database.insertRow(T.tableName, data: rowData)
        
        guard res.isSuccess, let row = res.data else {
            manager.errorMessage = res.error?.localizedDescription ?? "Insert failed"
            return nil
        }
        
        return T.fromRow(row)
    }
    
    // MARK: - Update
    
    @discardableResult
    static func update(_ model: T, manager: SelfDBManager, fileData: Data? = nil, filename: String? = nil, oldFileId: String? = nil, removeFile: Bool = false) async -> T? {
        guard let sdk = manager.selfDB,
              let modelId = model.id else { return nil }
        
        // Build the row data manually for updates
        var rowData: [String: Any] = [:]
        
        // Use the model's toRow method for updates too
        let modelData = model.toRow()
        for (key, value) in modelData {
            rowData[key] = value
        }
        
        // Handle file operations
        if removeFile {
            rowData["file_id"] = NSNull()
        } else if let data = fileData {
            // Remove old file if exists
            if let oldId = oldFileId {
                _ = await sdk.storage.deleteFile(oldId)
                FileURLCache.shared.invalidate(fileId: oldId)
            }
            
            // Upload new file
            if manager.bucketId == nil {
                await manager.ensureUserBucket()
            }
            
            if let name = filename,
               let bucket = manager.bucketId,
               let fileId = await manager.uploadFile(data: data, filename: name, bucketId: bucket) {
                rowData["file_id"] = fileId
            }
        }
        
        let res = await sdk.database.updateRow(T.tableName, rowId: modelId, data: rowData)
        
        guard res.isSuccess, let row = res.data else {
            manager.errorMessage = res.error?.localizedDescription ?? "Update failed"
            return nil
        }
        
        return T.fromRow(row)
    }
    
    // MARK: - Delete
    
    @discardableResult
    static func delete(_ model: T, manager: SelfDBManager) async -> Bool {
        guard let sdk = manager.selfDB,
              let modelId = model.id else { return false }
        
        // Delete associated file if model supports it and has a file
        if let fileAttachable = model as? (any SelfDBFileAttachable),
           let fileId = fileAttachable.fileId,
           !fileId.isEmpty {
            
            // Use the SelfDB SDK delete file method
            let deleteFileResult = await sdk.storage.deleteFile(fileId)
            if deleteFileResult.isSuccess {
                // Also invalidate the cache
                FileURLCache.shared.invalidate(fileId: fileId)
                manager.log("✅ Deleted file \(fileId) for \(T.tableName) \(modelId)")
            } else {
                manager.log("⚠️ Failed to delete file \(fileId): \(deleteFileResult.error?.localizedDescription ?? "Unknown error")")
                // Continue with record deletion even if file deletion fails
            }
        }
        
        // Delete the database record
        let res = await sdk.database.deleteRow(T.tableName, rowId: modelId)
        
        if !res.isSuccess {
            manager.errorMessage = res.error?.localizedDescription ?? "Delete failed"
            manager.log("❌ Failed to delete \(T.tableName) \(modelId): \(res.error?.localizedDescription ?? "Unknown error")")
        } else {
            manager.log("✅ Deleted \(T.tableName) \(modelId)")
        }
        
        return res.isSuccess
    }
    
    // MARK: - Fetch
    
    static func fetchAll(manager: SelfDBManager, page: Int = 1, pageSize: Int = 100, orderBy: String? = "created_at", descending: Bool = true) async -> [T] {
        guard let sdk = manager.selfDB else { return [] }
        
        let res = await sdk.database.getTableData(T.tableName, page: page, pageSize: pageSize)
        
        guard res.isSuccess, let table = res.data else {
            if let err = res.error {
                manager.errorMessage = err.localizedDescription
            }
            return []
        }
        
        let models = table.data.compactMap(T.fromRow)
        
        // Sort if requested (since SelfDB doesn't support ORDER BY in the API yet)
        if let orderField = orderBy {
            return models.sorted { first, second in
                guard let firstValue = Mirror(reflecting: first).children.first(where: { $0.label == orderField })?.value as? String,
                      let secondValue = Mirror(reflecting: second).children.first(where: { $0.label == orderField })?.value as? String else {
                    return false
                }
                return descending ? firstValue > secondValue : firstValue < secondValue
            }
        }
        
        return models
    }
    
    static func fetch(filterColumn: String, filterValue: String, manager: SelfDBManager, page: Int = 1, pageSize: Int = 100) async -> [T] {
        guard let sdk = manager.selfDB else { return [] }
        
        let res = await sdk.database.getTableData(
            T.tableName,
            page: page,
            pageSize: pageSize,
            filterColumn: filterColumn,
            filterValue: filterValue
        )
        
        guard res.isSuccess, let table = res.data else {
            if let err = res.error {
                manager.errorMessage = err.localizedDescription
            }
            return []
        }
        
        return table.data.compactMap(T.fromRow)
    }
    
    // MARK: - Count
    
    static func count(filterColumn: String? = nil, filterValue: String? = nil, manager: SelfDBManager) async -> Int {
        guard let sdk = manager.selfDB else { return 0 }
        
        let res = if let column = filterColumn, let value = filterValue {
            await sdk.database.getTableData(
                T.tableName,
                page: 1,
                pageSize: 1,
                filterColumn: column,
                filterValue: value
            )
        } else {
            await sdk.database.getTableData(T.tableName, page: 1, pageSize: 1)
        }
        
        return res.data?.metadata.total_count ?? 0
    }
}

