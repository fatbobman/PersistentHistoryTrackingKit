//
//  Merger.swift
//
//
//  Created by Yang Xu on 2022/2/12
//  Copyright © 2022 Yang Xu. All rights reserved.
//
//  Follow me on Twitter: @fatbobman
//  My Blog: https://www.fatbobman.com
//  微信公共号: 肘子的Swift记事本
//

import CoreData
import Foundation

struct PersistentHistoryTrackKitMerger: PersistentHistoryTrackKitMergerProtocol {
    var backgroundContext: NSManagedObjectContext
    func callAsFunction(merge transactions: [NSPersistentHistoryTransaction], into contexts: [NSManagedObjectContext]) {
        backgroundContext.performAndWait {
            for transaction in transactions {
                let userInfo = transaction.objectIDNotification().userInfo ?? [:]
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: userInfo, into: contexts)
            }
        }
    }
}
