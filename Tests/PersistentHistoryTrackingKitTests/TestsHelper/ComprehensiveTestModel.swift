//
//  ComprehensiveTestModel.swift
//
//
//  Created by Claude on 2025/6/27
//  Copyright © 2025 Anthropic. All rights reserved.
//

@preconcurrency import CoreData
import Foundation

/// 更复杂的测试模型，包含多个实体和关系
class ComprehensiveTestModel {
    
    static func createManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        
        // User 实体
        let userEntity = NSEntityDescription()
        userEntity.name = "User"
        userEntity.managedObjectClassName = "TestUser"
        
        let userIdAttribute = NSAttributeDescription()
        userIdAttribute.name = "userID"
        userIdAttribute.attributeType = .UUIDAttributeType
        userIdAttribute.isOptional = false
        
        let userNameAttribute = NSAttributeDescription()
        userNameAttribute.name = "name"
        userNameAttribute.attributeType = .stringAttributeType
        userNameAttribute.isOptional = false
        
        let userEmailAttribute = NSAttributeDescription()
        userEmailAttribute.name = "email"
        userEmailAttribute.attributeType = .stringAttributeType
        userEmailAttribute.isOptional = true
        
        let userCreatedAtAttribute = NSAttributeDescription()
        userCreatedAtAttribute.name = "createdAt"
        userCreatedAtAttribute.attributeType = .dateAttributeType
        userCreatedAtAttribute.isOptional = false
        
        userEntity.properties = [userIdAttribute, userNameAttribute, userEmailAttribute, userCreatedAtAttribute]
        
        // Post 实体
        let postEntity = NSEntityDescription()
        postEntity.name = "Post"
        postEntity.managedObjectClassName = "TestPost"
        
        let postIdAttribute = NSAttributeDescription()
        postIdAttribute.name = "postID"
        postIdAttribute.attributeType = .UUIDAttributeType
        postIdAttribute.isOptional = false
        
        let postTitleAttribute = NSAttributeDescription()
        postTitleAttribute.name = "title"
        postTitleAttribute.attributeType = .stringAttributeType
        postTitleAttribute.isOptional = false
        
        let postContentAttribute = NSAttributeDescription()
        postContentAttribute.name = "content"
        postContentAttribute.attributeType = .stringAttributeType
        postContentAttribute.isOptional = true
        
        let postCreatedAtAttribute = NSAttributeDescription()
        postCreatedAtAttribute.name = "createdAt"
        postCreatedAtAttribute.attributeType = .dateAttributeType
        postCreatedAtAttribute.isOptional = false
        
        let postViewCountAttribute = NSAttributeDescription()
        postViewCountAttribute.name = "viewCount"
        postViewCountAttribute.attributeType = .integer32AttributeType
        postViewCountAttribute.defaultValue = 0
        
        postEntity.properties = [postIdAttribute, postTitleAttribute, postContentAttribute, postCreatedAtAttribute, postViewCountAttribute]
        
        // Comment 实体
        let commentEntity = NSEntityDescription()
        commentEntity.name = "Comment"
        commentEntity.managedObjectClassName = "TestComment"
        
        let commentIdAttribute = NSAttributeDescription()
        commentIdAttribute.name = "commentID"
        commentIdAttribute.attributeType = .UUIDAttributeType
        commentIdAttribute.isOptional = false
        
        let commentTextAttribute = NSAttributeDescription()
        commentTextAttribute.name = "text"
        commentTextAttribute.attributeType = .stringAttributeType
        commentTextAttribute.isOptional = false
        
        let commentCreatedAtAttribute = NSAttributeDescription()
        commentCreatedAtAttribute.name = "createdAt"
        commentCreatedAtAttribute.attributeType = .dateAttributeType
        commentCreatedAtAttribute.isOptional = false
        
        commentEntity.properties = [commentIdAttribute, commentTextAttribute, commentCreatedAtAttribute]
        
        // 设置关系
        
        // User -> Posts (一对多)
        let userPostsRelationship = NSRelationshipDescription()
        userPostsRelationship.name = "posts"
        userPostsRelationship.destinationEntity = postEntity
        userPostsRelationship.isOptional = true
        userPostsRelationship.maxCount = 0 // 表示一对多
        userPostsRelationship.deleteRule = .cascadeDeleteRule
        
        let postUserRelationship = NSRelationshipDescription()
        postUserRelationship.name = "author"
        postUserRelationship.destinationEntity = userEntity
        postUserRelationship.isOptional = false
        postUserRelationship.maxCount = 1
        postUserRelationship.deleteRule = .nullifyDeleteRule
        
        userPostsRelationship.inverseRelationship = postUserRelationship
        postUserRelationship.inverseRelationship = userPostsRelationship
        
        // User -> Comments (一对多)
        let userCommentsRelationship = NSRelationshipDescription()
        userCommentsRelationship.name = "comments"
        userCommentsRelationship.destinationEntity = commentEntity
        userCommentsRelationship.isOptional = true
        userCommentsRelationship.maxCount = 0
        userCommentsRelationship.deleteRule = .cascadeDeleteRule
        
        let commentUserRelationship = NSRelationshipDescription()
        commentUserRelationship.name = "author"
        commentUserRelationship.destinationEntity = userEntity
        commentUserRelationship.isOptional = false
        commentUserRelationship.maxCount = 1
        commentUserRelationship.deleteRule = .nullifyDeleteRule
        
        userCommentsRelationship.inverseRelationship = commentUserRelationship
        commentUserRelationship.inverseRelationship = userCommentsRelationship
        
        // Post -> Comments (一对多)
        let postCommentsRelationship = NSRelationshipDescription()
        postCommentsRelationship.name = "comments"
        postCommentsRelationship.destinationEntity = commentEntity
        postCommentsRelationship.isOptional = true
        postCommentsRelationship.maxCount = 0
        postCommentsRelationship.deleteRule = .cascadeDeleteRule
        
        let commentPostRelationship = NSRelationshipDescription()
        commentPostRelationship.name = "post"
        commentPostRelationship.destinationEntity = postEntity
        commentPostRelationship.isOptional = false
        commentPostRelationship.maxCount = 1
        commentPostRelationship.deleteRule = .nullifyDeleteRule
        
        postCommentsRelationship.inverseRelationship = commentPostRelationship
        commentPostRelationship.inverseRelationship = postCommentsRelationship
        
        // 添加关系到实体
        userEntity.properties.append(contentsOf: [userPostsRelationship, userCommentsRelationship])
        postEntity.properties.append(contentsOf: [postUserRelationship, postCommentsRelationship])
        commentEntity.properties.append(contentsOf: [commentUserRelationship, commentPostRelationship])
        
        model.entities = [userEntity, postEntity, commentEntity]
        return model
    }
    
    static func createContainer(storeURL: URL) -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "ComprehensiveTestModel", managedObjectModel: createManagedObjectModel())
        
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        
        // 启用持久化历史跟踪
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        // 启用 Core Data 并发调试
        description.setOption(true as NSNumber, forKey: "NSCoreDataConcurrencyDebug")
        description.setOption(1 as NSNumber, forKey: "com.apple.CoreData.ConcurrencyDebug")
        
        container.persistentStoreDescriptions = [description]
        
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        
        if let error = loadError {
            fatalError("Failed to load store: \(error)")
        }
        
        // 为主上下文启用额外的并发检查
        container.viewContext.shouldDeleteInaccessibleFaults = false
        
        return container
    }
}

// MARK: - 测试实体类

@objc(TestUser)
class TestUser: NSManagedObject {
    @NSManaged var userID: UUID
    @NSManaged var name: String
    @NSManaged var email: String?
    @NSManaged var createdAt: Date
    @NSManaged var posts: Set<TestPost>
    @NSManaged var comments: Set<TestComment>
    
    convenience init(context: NSManagedObjectContext, name: String, email: String? = nil) {
        self.init(context: context)
        self.userID = UUID()
        self.name = name
        self.email = email
        self.createdAt = Date()
    }
}

@objc(TestPost)
class TestPost: NSManagedObject {
    @NSManaged var postID: UUID
    @NSManaged var title: String
    @NSManaged var content: String?
    @NSManaged var createdAt: Date
    @NSManaged var viewCount: Int32
    @NSManaged var author: TestUser
    @NSManaged var comments: Set<TestComment>
    
    convenience init(context: NSManagedObjectContext, title: String, content: String?, author: TestUser) {
        self.init(context: context)
        self.postID = UUID()
        self.title = title
        self.content = content
        self.createdAt = Date()
        self.viewCount = 0
        self.author = author
    }
}

@objc(TestComment)
class TestComment: NSManagedObject {
    @NSManaged var commentID: UUID
    @NSManaged var text: String
    @NSManaged var createdAt: Date
    @NSManaged var author: TestUser
    @NSManaged var post: TestPost
    
    convenience init(context: NSManagedObjectContext, text: String, author: TestUser, post: TestPost) {
        self.init(context: context)
        self.commentID = UUID()
        self.text = text
        self.createdAt = Date()
        self.author = author
        self.post = post
    }
}