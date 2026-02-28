//
//  TestAppDataHandler.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Codex on 2026-02-28.
//

import CoreData
import CoreDataEvolution
import Foundation

@testable import PersistentHistoryTrackingKit

struct PersonUpdate: Sendable {
  let matchName: String
  let newName: String?
  let newAge: Int32?

  init(matchName: String, newName: String? = nil, newAge: Int32? = nil) {
    self.matchName = matchName
    self.newName = newName
    self.newAge = newAge
  }
}

@NSModelActor(disableGenerateInit: true)
actor TestAppDataHandler {
  init(
    container: NSPersistentContainer,
    context: NSManagedObjectContext? = nil,
    viewName: String
  ) {
    modelContainer = container
    let context = context ?? container.newBackgroundContext()
    context.name = viewName
    modelExecutor = .init(context: context)
  }

  @discardableResult
  func createPerson(
    name: String,
    age: Int32,
    author: String,
    id: UUID = UUID()
  ) throws -> URL {
    modelContext.transactionAuthor = author
    let person = TestModelBuilder.createPerson(name: name, age: age, in: modelContext)
    person.setValue(id, forKey: "id")
    try modelContext.save()
    return person.objectID.uriRepresentation()
  }

  func createPeople(
    _ people: [(String, Int32)],
    author: String
  ) throws {
    modelContext.transactionAuthor = author
    for (name, age) in people {
      TestModelBuilder.createPerson(name: name, age: age, in: modelContext)
    }
    try modelContext.save()
  }

  func createPeople(
    count: Int,
    author: String,
    namePrefix: String = "Person",
    startingAge: Int32 = 20
  ) throws {
    let people = (0..<count).map { index in
      ("\(namePrefix)\(index)", startingAge + Int32(index))
    }
    try createPeople(people, author: author)
  }

  @discardableResult
  func createItem(
    title: String,
    author: String
  ) throws -> URL {
    modelContext.transactionAuthor = author
    let item = TestModelBuilder.createItem(title: title, in: modelContext)
    try modelContext.save()
    return item.objectID.uriRepresentation()
  }

  func createItems(
    _ titles: [String],
    author: String
  ) throws {
    modelContext.transactionAuthor = author
    for title in titles {
      TestModelBuilder.createItem(title: title, in: modelContext)
    }
    try modelContext.save()
  }

  func createPeopleAndItems(
    people: [(String, Int32)],
    items: [String],
    author: String
  ) throws {
    modelContext.transactionAuthor = author
    for (name, age) in people {
      TestModelBuilder.createPerson(name: name, age: age, in: modelContext)
    }
    for title in items {
      TestModelBuilder.createItem(title: title, in: modelContext)
    }
    try modelContext.save()
  }

  func updatePeople(
    _ updates: [PersonUpdate],
    author: String
  ) throws {
    modelContext.transactionAuthor = author
    for update in updates {
      guard let person = try fetchPerson(named: update.matchName) else {
        continue
      }
      if let newName = update.newName {
        person.setValue(newName, forKey: "name")
      }
      if let newAge = update.newAge {
        person.setValue(newAge, forKey: "age")
      }
    }
    try modelContext.save()
  }

  func updatePeopleAndCreatePeople(
    updates: [PersonUpdate],
    newPeople: [(String, Int32)],
    author: String
  ) throws {
    modelContext.transactionAuthor = author
    for update in updates {
      guard let person = try fetchPerson(named: update.matchName) else {
        continue
      }
      if let newName = update.newName {
        person.setValue(newName, forKey: "name")
      }
      if let newAge = update.newAge {
        person.setValue(newAge, forKey: "age")
      }
    }
    for (name, age) in newPeople {
      TestModelBuilder.createPerson(name: name, age: age, in: modelContext)
    }
    try modelContext.save()
  }

  func deletePeople(
    named names: [String],
    author: String
  ) throws {
    modelContext.transactionAuthor = author
    for name in names {
      if let person = try fetchPerson(named: name) {
        modelContext.delete(person)
      }
    }
    try modelContext.save()
  }

  func deletePeopleAndCreateEntities(
    deleteNames: [String],
    newPeople: [(String, Int32)],
    newItems: [String],
    author: String
  ) throws {
    modelContext.transactionAuthor = author
    for name in deleteNames {
      if let person = try fetchPerson(named: name) {
        modelContext.delete(person)
      }
    }
    for (name, age) in newPeople {
      TestModelBuilder.createPerson(name: name, age: age, in: modelContext)
    }
    for title in newItems {
      TestModelBuilder.createItem(title: title, in: modelContext)
    }
    try modelContext.save()
  }

  func personCount() throws -> Int {
    let request = NSFetchRequest<NSManagedObject>(entityName: "Person")
    return try modelContext.fetch(request).count
  }

  func personNames() throws -> [String] {
    try personSummaries().map(\.0)
  }

  func personSummaries() throws -> [(String, Int32)] {
    let request = NSFetchRequest<NSManagedObject>(entityName: "Person")
    request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
    return try modelContext.fetch(request).compactMap { person in
      guard
        let name = person.value(forKey: "name") as? String,
        let age = person.value(forKey: "age") as? Int32
      else { return nil }
      return (name, age)
    }
  }

  func itemCount() throws -> Int {
    let request = NSFetchRequest<NSManagedObject>(entityName: "Item")
    return try modelContext.fetch(request).count
  }

  func historyOrderedKeys(for author: String) throws -> [String] {
    let request = NSPersistentHistoryChangeRequest.fetchHistory(
      after: nil as NSPersistentHistoryToken?)
    let fetchRequest = NSPersistentHistoryTransaction.fetchRequest!
    fetchRequest.predicate = NSPredicate(format: "author == %@", author)
    request.fetchRequest = fetchRequest

    guard
      let result = try modelContext.execute(request) as? NSPersistentHistoryResult,
      var transactions = result.result as? [NSPersistentHistoryTransaction]
    else {
      return []
    }

    transactions.sort { $0.timestamp < $1.timestamp }

    guard let lastTransaction = transactions.last, let changes = lastTransaction.changes else {
      return []
    }

    var seenKeys = Set<String>()
    var orderedKeys: [String] = []

    for change in changes {
      let entityName = change.changedObjectID.entity.name ?? "Unknown"
      let operation: HookOperation =
        switch change.changeType {
        case .insert:
          .insert
        case .update:
          .update
        case .delete:
          .delete
        @unknown default:
          .update
        }
      let key = "\(entityName).\(operation.rawValue)"
      if seenKeys.insert(key).inserted {
        orderedKeys.append(key)
      }
    }

    return orderedKeys
  }

  private func fetchPerson(named name: String) throws -> NSManagedObject? {
    let request = NSFetchRequest<NSManagedObject>(entityName: "Person")
    request.predicate = NSPredicate(format: "name == %@", name)
    request.fetchLimit = 1
    return try modelContext.fetch(request).first
  }
}
