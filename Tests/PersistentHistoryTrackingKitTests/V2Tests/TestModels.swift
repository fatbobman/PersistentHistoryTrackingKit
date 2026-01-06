//
//  TestModels.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Claude on 2025-01-06
//

import CoreData
import Foundation

/// 测试用的 Core Data Stack Helper
/// 纯代码创建 NSManagedObjectModel，包含两个 Entity：Person 和 Item
enum TestModelBuilder {

    /// 创建测试用的 NSManagedObjectModel
    /// - Returns: 包含 Person 和 Item 两个 Entity 的 Model
    static func createModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // 创建 Person Entity（带墓碑）
        let personEntity = NSEntityDescription()
        personEntity.name = "Person"
        personEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        // Person 属性
        let personNameAttribute = NSAttributeDescription()
        personNameAttribute.name = "name"
        personNameAttribute.attributeType = .stringAttributeType
        personNameAttribute.isOptional = false
        // Note: 墓碑属性需要在 xcdatamodel 中通过 Xcode 设置
        // 或者使用 NSPersistentHistoryTransaction 的 tombstone API

        let personAgeAttribute = NSAttributeDescription()
        personAgeAttribute.name = "age"
        personAgeAttribute.attributeType = .integer32AttributeType
        personAgeAttribute.isOptional = false
        personAgeAttribute.defaultValue = 0

        let personIDAttribute = NSAttributeDescription()
        personIDAttribute.name = "id"
        personIDAttribute.attributeType = .UUIDAttributeType
        personIDAttribute.isOptional = false
        personIDAttribute.defaultValue = UUID()

        personEntity.properties = [personNameAttribute, personAgeAttribute, personIDAttribute]

        // 创建 Item Entity（不带墓碑）
        let itemEntity = NSEntityDescription()
        itemEntity.name = "Item"
        itemEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        // Item 属性
        let itemTitleAttribute = NSAttributeDescription()
        itemTitleAttribute.name = "title"
        itemTitleAttribute.attributeType = .stringAttributeType
        itemTitleAttribute.isOptional = false

        let itemIDAttribute = NSAttributeDescription()
        itemIDAttribute.name = "id"
        itemIDAttribute.attributeType = .UUIDAttributeType
        itemIDAttribute.isOptional = false
        itemIDAttribute.defaultValue = UUID()

        let itemTimestampAttribute = NSAttributeDescription()
        itemTimestampAttribute.name = "timestamp"
        itemTimestampAttribute.attributeType = .dateAttributeType
        itemTimestampAttribute.isOptional = false
        itemTimestampAttribute.defaultValue = Date()

        itemEntity.properties = [itemTitleAttribute, itemIDAttribute, itemTimestampAttribute]

        // 添加 Entity 到 Model
        model.entities = [personEntity, itemEntity]

        return model
    }

    /// 创建测试用的 NSPersistentContainer（SQLite 文件）
    /// - Parameters:
    ///   - author: Transaction author
    ///   - testName: 测试名称（用于生成唯一的数据库文件名）
    /// - Returns: 配置好的容器
    static func createContainer(author: String, testName: String = #function) -> NSPersistentContainer {
        let model = createModel()
        let container = NSPersistentContainer(name: "TestModel", managedObjectModel: model)

        // 使用 SQLite Store（支持 Persistent History）
        let tempDir = FileManager.default.temporaryDirectory
        let storeURL = tempDir.appendingPathComponent("TestModel_\(testName).sqlite")

        // 删除旧文件（如果存在）
        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("sqlite-shm"))
        try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("sqlite-wal"))

        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false

        // 启用 Persistent History Tracking
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }

        if let error = loadError {
            fatalError("Failed to load store: \(error)")
        }

        // 配置 viewContext
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        container.viewContext.transactionAuthor = author

        return container
    }

    /// 创建 Person 对象
    @discardableResult
    static func createPerson(
        name: String,
        age: Int32,
        in context: NSManagedObjectContext
    ) -> NSManagedObject {
        let person = NSEntityDescription.insertNewObject(
            forEntityName: "Person",
            into: context
        )
        person.setValue(name, forKey: "name")
        person.setValue(age, forKey: "age")
        person.setValue(UUID(), forKey: "id")
        return person
    }

    /// 创建 Item 对象
    @discardableResult
    static func createItem(
        title: String,
        in context: NSManagedObjectContext
    ) -> NSManagedObject {
        let item = NSEntityDescription.insertNewObject(
            forEntityName: "Item",
            into: context
        )
        item.setValue(title, forKey: "title")
        item.setValue(UUID(), forKey: "id")
        item.setValue(Date(), forKey: "timestamp")
        return item
    }
}
