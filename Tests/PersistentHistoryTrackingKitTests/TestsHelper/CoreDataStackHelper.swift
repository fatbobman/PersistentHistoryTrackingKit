//
//  File.swift
//
//
//  Created by Yang Xu on 2022/2/11
//  Copyright © 2022 Yang Xu. All rights reserved.
//
//  Follow me on Twitter: @fatbobman
//  My Blog: https://www.fatbobman.com
//  微信公共号: 肘子的Swift记事本
//

@preconcurrency import CoreData
import Foundation

class CoreDataHelper {
    static func createNSPersistentContainer(
        storeURL: URL? = URL(fileURLWithPath: "/dev/null"),
        enablePersistentHistoryTrack: Bool = true
    ) -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "Test Model", managedObjectModel: Self.model)
        guard let desc = container.persistentStoreDescriptions.first else {
            fatalError()
        }
        desc.url = storeURL
        if enablePersistentHistoryTrack {
            desc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            desc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }
        
        // 启用 Core Data 并发调试
        desc.setOption(true as NSNumber, forKey: "NSCoreDataConcurrencyDebug")
        desc.setOption(1 as NSNumber, forKey: "com.apple.CoreData.ConcurrencyDebug")
        
        container.persistentStoreDescriptions = [desc]
        container.loadPersistentStores(completionHandler: { _, error in
            if let error = error {
                fatalError("create container error : \(error.localizedDescription)")
            }
        })
        
        // 为主上下文启用并发调试
        container.viewContext.shouldDeleteInaccessibleFaults = false
        
        return container
    }

    /// 创建一个NSManagedObjectModel  Entity: Event property: timestamp
    static func createTestNSManagedObjectModelModel() -> NSManagedObjectModel {
        let eventEntity = NSEntityDescription()
        eventEntity.name = "Event"
        eventEntity.managedObjectClassName = "Event"

        let timestampAttribute = NSAttributeDescription()

        if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
            timestampAttribute.type = .date
        } else {
            timestampAttribute.attributeType = .dateAttributeType
        }
        timestampAttribute.name = "timestamp"
        eventEntity.properties.append(timestampAttribute)

        let model = NSManagedObjectModel()
        model.entities = [eventEntity]
        return model
    }

    nonisolated(unsafe) static let model = createTestNSManagedObjectModelModel()
}

@objc(Event)
class Event: NSManagedObject {
    @NSManaged var timestamp: Date?
}
