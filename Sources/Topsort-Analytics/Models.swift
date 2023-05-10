//
//  File.swift
//  
//
//  Created by Pablo Reszczynski on 09-05-23.
//

import Foundation

enum EntityType : String, Codable {
    case product
    case vendor
}

struct Placement: Codable {
    let path: String
    let position: Int?
    let page: Int?
    let pageSize: Int?
    let productId: String?
    let categoryIds: [String]?
    let searchQuery: String?
    
    init(path: String, position: Int? = nil, page: Int? = nil, pageSize: Int? = nil, productId: String? = nil, categoryIds: [String]? = nil, searchQuery: String? = nil) {
        self.path = path
        self.position = position
        self.page = page
        self.pageSize = pageSize
        self.productId = productId
        self.categoryIds = categoryIds
        self.searchQuery = searchQuery
    }
}

struct Entity : Codable {
    let type: EntityType
    let id: String
}

struct Event : Codable {
    let entity: Entity
    let ocurredAt: Date
    let opaqueUserId: String
    let id: UUID
    let resolvedBidId: String?
    let placement: Placement?

    init(entity: Entity, ocurredAt: Date, opaqueUserId: String, resolvedBidId: String? = nil, placement: Placement? = nil) {
        self.entity = entity
        self.ocurredAt = ocurredAt
        self.opaqueUserId = opaqueUserId
        self.resolvedBidId = resolvedBidId
        self.placement = placement
        self.id = UUID()
    }
}

struct PurchaseItem : Codable {
    let productId: String
    let quantity: Int?
    let unitPrice: Double
    
    init(productId: String, unitPrice: Double, quantity: Int? = nil) {
        self.productId = productId
        self.quantity = quantity
        self.unitPrice = unitPrice
    }
}

struct PurchaseEvent : Codable {
    let ocurrentAt: Date
    let opaqueUserId: String
    let items: [PurchaseItem]
    let id: UUID
}

struct Events : Codable {
    let impressions: [Event]?
    let clicks: [Event]?
    let purchases: [PurchaseEvent]?
    
    init(impressions: [Event], clicks: [Event]? = nil, purchases: [PurchaseEvent]? = nil) {
        self.impressions = impressions
        self.clicks = clicks
        self.purchases = purchases
    }
    
    init(clicks: [Event], impressions: [Event]? = nil, purchases: [PurchaseEvent]? = nil) {
        self.impressions = impressions
        self.clicks = clicks
        self.purchases = purchases
    }
    
    init(purchases: [PurchaseEvent], impressions: [Event]? = nil, clicks: [Event]? = nil) {
        self.impressions = impressions
        self.clicks = clicks
        self.purchases = purchases
    }
}
