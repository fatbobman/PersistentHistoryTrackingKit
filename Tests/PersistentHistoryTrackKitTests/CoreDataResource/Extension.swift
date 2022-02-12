//
//  Extension.swift
//
//
//  Created by Yang Xu on 2022/2/11
//  Copyright © 2022 Yang Xu. All rights reserved.
//
//  Follow me on Twitter: @fatbobman
//  My Blog: https://www.fatbobman.com
//  微信公共号: 肘子的Swift记事本
//

import CoreData
import Foundation

extension NSManagedObjectContext {
    func saveIfChanged() {
        guard self.hasChanges else { return }
        do {
            try self.save()
        } catch {
            fatalError("Context save error: \(error.localizedDescription)")
        }
    }
}
