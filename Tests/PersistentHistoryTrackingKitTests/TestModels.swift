//
//  TestModels.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Claude on 2025-01-06
//

import CoreData
import Foundation

/// Core Data stack helper for tests.
/// Builds an NSManagedObjectModel entirely in code with two entities: Person and Item.
enum TestModelBuilder {
  /// Shared NSManagedObjectModel instance (thread-safe lazy initialization).
  /// - Note: Core Data expects a single model instance per schema; mixing instances can create
  /// concurrency issues.
  /// NSManagedObjectModel is thread-safe, so we mark it `nonisolated(unsafe)`.
  private nonisolated(unsafe) static let sharedModel: NSManagedObjectModel = {
    let model = NSManagedObjectModel()

    // Build the Person entity (with tombstone-friendly properties).
    let personEntity = NSEntityDescription()
    personEntity.name = "Person"
    personEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

    let personNameAttribute = NSAttributeDescription()
    personNameAttribute.name = "name"
    personNameAttribute.attributeType = .stringAttributeType
    personNameAttribute.isOptional = false
    // Preserve `name` in tombstones.
    personNameAttribute.preservesValueInHistoryOnDeletion = true

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
    // Preserve `id` in tombstones.
    personIDAttribute.preservesValueInHistoryOnDeletion = true

    personEntity.properties = [personNameAttribute, personAgeAttribute, personIDAttribute]

    // Build the Item entity.
    let itemEntity = NSEntityDescription()
    itemEntity.name = "Item"
    itemEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

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

    model.entities = [personEntity, itemEntity]
    return model
  }()

  /// Get the shared NSManagedObjectModel.
  /// - Returns: Shared model instance.
  static func createModel() -> NSManagedObjectModel {
    sharedModel
  }

  /// Create a test NSPersistentContainer (SQLite store).
  /// - Parameters:
  ///   - author: Transaction author
  ///   - testName: Test name used to build a unique store filename.
  /// - Returns: Configured container.
  static func createContainer(
    author: String,
    testName: String = #function
  ) -> NSPersistentContainer {
    let model = createModel()
    let container = NSPersistentContainer(name: "TestModel", managedObjectModel: model)

    // Use an SQLite store (required for persistent history).
    // Add a UUID suffix so parallel tests get unique filenames.
    let tempDir = FileManager.default.temporaryDirectory
    let uniqueId = UUID().uuidString.prefix(8)
    let storeURL = tempDir.appendingPathComponent("TestModel_\(testName)_\(uniqueId).sqlite")

    // Remove any stale files; the UUID normally keeps paths unique.
    try? FileManager.default.removeItem(at: storeURL)
    try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("sqlite-shm"))
    try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("sqlite-wal"))

    let description = NSPersistentStoreDescription(url: storeURL)
    description.type = NSSQLiteStoreType
    description.shouldAddStoreAsynchronously = false

    // Enable Persistent History Tracking.
    description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
    description.setOption(
      true as NSNumber,
      forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

    container.persistentStoreDescriptions = [description]

    var loadError: Error?
    container.loadPersistentStores { _, error in
      loadError = error
    }

    if let error = loadError {
      fatalError("Failed to load store: \(error)")
    }

    // Configure the viewContext.
    container.viewContext.automaticallyMergesChangesFromParent = true
    container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    container.viewContext.transactionAuthor = author

    return container
  }

  /// Create a Person object.
  @discardableResult
  static func createPerson(
    name: String,
    age: Int32,
    in context: NSManagedObjectContext
  ) -> NSManagedObject {
    let person = NSEntityDescription.insertNewObject(
      forEntityName: "Person",
      into: context)
    person.setValue(name, forKey: "name")
    person.setValue(age, forKey: "age")
    person.setValue(UUID(), forKey: "id")
    return person
  }

  /// Create an Item object.
  @discardableResult
  static func createItem(
    title: String,
    in context: NSManagedObjectContext
  ) -> NSManagedObject {
    let item = NSEntityDescription.insertNewObject(
      forEntityName: "Item",
      into: context)
    item.setValue(title, forKey: "title")
    item.setValue(UUID(), forKey: "id")
    item.setValue(Date(), forKey: "timestamp")
    return item
  }

  /// Create an isolated UserDefaults instance for testing.
  ///
  /// Each call returns a new suite to prevent cross-test contamination.
  /// - Returns: Fresh UserDefaults instance.
  static func createTestUserDefaults() -> UserDefaults {
    UserDefaults(suiteName: "test-\(UUID().uuidString)")!
  }
}
