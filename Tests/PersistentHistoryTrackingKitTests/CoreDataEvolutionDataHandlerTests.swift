//
//  CoreDataEvolutionDataHandlerTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Codex on 2026-02-28.
//

import CoreData
import CoreDataEvolution
import Testing

@testable import PersistentHistoryTrackingKit

@NSModelActor(disableGenerateInit: true)
private actor TestPersonDataHandler {
  init(container: NSPersistentContainer, viewName: String) {
    modelContainer = container
    let context = container.newBackgroundContext()
    context.name = viewName
    modelExecutor = .init(context: context)
  }

  @discardableResult
  func createPerson(
    name: String,
    age: Int32,
    author: String
  ) throws -> NSManagedObjectID {
    modelContext.transactionAuthor = author

    let person = NSEntityDescription.insertNewObject(
      forEntityName: "Person",
      into: modelContext)
    person.setValue(name, forKey: "name")
    person.setValue(age, forKey: "age")
    person.setValue(UUID(), forKey: "id")

    try modelContext.save()
    return person.objectID
  }
}

@Suite("CoreDataEvolution Data Handler Tests", .serialized)
struct CoreDataEvolutionDataHandlerTests {
  @Test("Actor-based test data creation works with transaction processing")
  func actorBasedDataCreationWorksWithTransactionProcessing() async throws {
    let container = TestModelBuilder.createContainer(
      author: "Seeder",
      testName: "actorBasedDataCreationWorksWithTransactionProcessing")
    let writer = TestPersonDataHandler(container: container, viewName: "writer")
    let mergeContext = container.newBackgroundContext()
    mergeContext.transactionAuthor = "App2"

    try await writer.createPerson(name: "Alice", age: 30, author: "App1")
    try await Task.sleep(nanoseconds: 100_000_000)
    try await writer.createPerson(name: "Bob", age: 31, author: "App1")

    let countBeforeProcessing = try await writer.withContext { context in
      let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
      return try context.fetch(fetchRequest).count
    }
    #expect(countBeforeProcessing == 2)

    let hookRegistry = HookRegistryActor()
    let timestampManager = TransactionTimestampManager(
      userDefaults: TestModelBuilder.createTestUserDefaults(),
      maximumDuration: 604_800)
    let processor = TransactionProcessorActor(
      container: container,
      contexts: [mergeContext],
      hookRegistry: hookRegistry,
      cleanStrategy: .none,
      timestampManager: timestampManager)

    _ = try await processor.processNewTransactionsWithTimestampManagement(
      from: ["App1", "App2"],
      after: nil,
      currentAuthor: "App2")

    let remainingTransactionCount = try await processor.testTransactionCount(
      from: ["App1", "App2"],
      after: nil)
    #expect(remainingTransactionCount == 2)

    try await mergeContext.perform {
      let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
      let results = try mergeContext.fetch(fetchRequest)
      #expect(results.count == 2)
    }
  }
}
