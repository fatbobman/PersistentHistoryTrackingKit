//
//  MergerProtocol.swift
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

protocol TransactionMergerProtocol {
    /// 将 transaction 合并到指定的托管对象上下文。可以多个上下文，之间用 ，分隔
    func callAsFunction(merge transactions: [NSPersistentHistoryTransaction], into contexts: [NSManagedObjectContext])
}
