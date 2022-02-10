//
//  TransactionTimestampManagerProtocol.swift
//
//
//  Created by Yang Xu on 2022/2/10
//  Copyright © 2022 Yang Xu. All rights reserved.
//
//  Follow me on Twitter: @fatbobman
//  My Blog: https://www.fatbobman.com
//  微信公共号: 肘子的Swift记事本
//

import Foundation

protocol TransactionTimestampManagerProtocol {
    func getLastCommonTransactionTimestamp(in authors: [String]) -> Date?
    func updateLastHistoryTransactionTimestamp(for author: String, to newDate: Date?)
}
