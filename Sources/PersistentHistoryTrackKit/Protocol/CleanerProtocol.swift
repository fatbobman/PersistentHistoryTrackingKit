//
//  CleanerProtocol.swift
//  
//
//  Created by Yang Xu on 2022/2/11
//  Copyright © 2022 Yang Xu. All rights reserved.
//
//  Follow me on Twitter: @fatbobman 
//  My Blog: https://www.fatbobman.com
//  微信公共号: 肘子的Swift记事本
//


import Foundation
import CoreData

protocol PersistentHistoryTrackKitCleanerProtocol{
    var backgroundContext:NSManagedObjectContext{get}
    var authors:[String]{get}
    var logger:PersistentHistoryTrackKitLoggerProtocol?{get}
    var timastampManager:TransactionTimestampManager{get}
    func cleanTransaction(before timestamp:Date?) -> Int
}
