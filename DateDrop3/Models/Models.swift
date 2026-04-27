//
//  Models.swift
//  DateDrop3
//
//  数据模型定义
//

import Foundation

// MARK: - 用户模型
struct User: Codable, Identifiable, Equatable {
    let id: Int
    let nickname: String
    let age: Int
    let gender: String
    let school_career: String?
    let city: String
    let contact: String?
    let avatar_url: String?
    var matches_left: Int
    let is_verified: Bool
    let created_at: String?

    enum CodingKeys: String, CodingKey {
        case id, nickname, age, gender, city
        case school_career
        case contact
        case avatar_url
        case matches_left
        case is_verified
        case created_at
    }
}

// MARK: - 问卷题目模型
struct Question: Codable, Identifiable {
    let id: Int
    let text: String
    let isLikert: Bool
    let isSensitive: Bool
    let section: String?
    let weight: Double?

    enum CodingKeys: String, CodingKey {
        case id, text, section, weight
        case isLikert
        case isSensitive
        case is_likert
        case is_sensitive
    }

    init(id: Int, text: String, isLikert: Bool, isSensitive: Bool, section: String?, weight: Double?) {
        self.id = id
        self.text = text
        self.isLikert = isLikert
        self.isSensitive = isSensitive
        self.section = section
        self.weight = weight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(Int.self, forKey: .id)
        let text = try container.decode(String.self, forKey: .text)
        let section = try container.decodeIfPresent(String.self, forKey: .section)
        let weight = try container.decodeIfPresent(Double.self, forKey: .weight)
        let isLikert = try container.decodeIfPresent(Bool.self, forKey: .isLikert)
            ?? container.decode(Bool.self, forKey: .is_likert)
        let isSensitive = try container.decodeIfPresent(Bool.self, forKey: .isSensitive)
            ?? container.decode(Bool.self, forKey: .is_sensitive)
        self.init(id: id, text: text, isLikert: isLikert, isSensitive: isSensitive, section: section, weight: weight)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(isLikert, forKey: .isLikert)
        try container.encode(isSensitive, forKey: .isSensitive)
        try container.encodeIfPresent(section, forKey: .section)
        try container.encodeIfPresent(weight, forKey: .weight)
    }
}

struct QuestionsResponse: Codable {
    let questions: [Question]
    let total: Int
}

struct QuestionsBySection: Codable {
    let sections: [String: [Question]]

    enum CodingKeys: String, CodingKey {
        case sections
        case data
    }

    init(sections: [String: [Question]]) {
        self.sections = sections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 尝试顶层 sections
        if let sections = try? container.decode([String: [Question]].self, forKey: .sections) {
            self.sections = sections
            return
        }
        // 尝试 data.sections 包裹
        if container.contains(.data) {
            let dataContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .data)
            if let sections = try? dataContainer.decode([String: [Question]].self, forKey: .sections) {
                self.sections = sections
                return
            }
        }
        // 兜底空
        self.sections = [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sections, forKey: .sections)
    }
}

// MARK: - 答案模型
struct Answer: Codable {
    let question_id: Int
    let answer: Int
}

struct AnswerSubmitRequest: Codable {
    let answers: [Answer]
}

struct GenerateMatchesRequest: Codable {
    let lang: String
}

struct AnswerStatusResponse: Codable {
    let completed: Bool
    let answered_count: Int
    let total: Int
}

struct TranslateRequest: Codable {
    let text: String
    let target_language: String
}

struct TranslateResponse: Codable {
    let translated_text: String
    let target_language: String
}

// MARK: - 匹配模型
struct Match: Codable, Identifiable, Hashable {
    let id: Int
    let user1_id: Int
    let user2_id: Int
    let similarity_score: Double
    let status: String
    let is_unlocked: Bool
    let chat_message_count: Int
    let created_at: String?
    let last_message_at: String?
    let last_message_sender_id: Int?
    let unread_count: Int?
    let ai_intro: String?
    let partner_nickname: String?

    enum CodingKeys: String, CodingKey {
        case id
        case user1_id
        case user2_id
        case similarity_score
        case status
        case is_unlocked
        case chat_message_count
        case created_at
        case last_message_at
        case last_message_sender_id
        case unread_count
        case ai_intro
        case partner_nickname
    }

    // 获取匹配对象的用户ID (对于当前用户)
    func getPartnerUserId(currentUserId: Int) -> Int {
        return user1_id == currentUserId ? user2_id : user1_id
    }

    func getPartnerDisplayCode(currentUserId: Int?) -> String {
        let seed = currentUserId != nil ? getPartnerUserId(currentUserId: currentUserId!) : id
        return Match.formatCode(seed)
    }

    private static func formatCode(_ seed: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var value = UInt64(seed) &+ 0x9E3779B97F4A7C15
        var code = ""
        for _ in 0..<5 {
            value ^= value >> 12
            value ^= value << 25
            value ^= value >> 27
            let index = Int(value % UInt64(chars.count))
            code.append(chars[index])
        }
        return "U-\(code)"
    }
}

struct MatchesResponse: Codable {
    let matches: [Match]
    let total: Int
}

struct GenerateMatchesResponse: Codable {
    let message: String
    let matches: [Match]
    let matches_left: Int
}

// MARK: - 聊天消息模型
struct ChatMessage: Codable, Identifiable {
    let id: Int
    let match_id: Int
    let sender_id: Int
    let content: String
    let message_type: String
    let is_read: Bool
    let created_at: String?

    enum CodingKeys: String, CodingKey {
        case id
        case match_id
        case sender_id
        case content
        case message_type
        case is_read
        case created_at
    }
}

struct MessagesResponse: Codable {
    let messages: [ChatMessage]
    let total: Int
}

// MARK: - 评分模型
struct RatingSubmitRequest: Codable {
    let match_id: Int
    let score: Int
    let user_id: Int?
}

struct Rating: Codable {
    let id: Int
    let match_id: Int
    let rater_id: Int
    let rated_user_id: Int
    let score: Int
    let created_at: String?
}

struct RatingStatusResponse: Codable {
    let match_id: Int
    let both_rated: Bool
    let is_unlocked: Bool
    let ratings_count: Int
}

struct UnlockStatusResponse: Codable {
    let match_id: Int
    let can_unlock: Bool
    let reason: String
    let is_unlocked: Bool
}

// MARK: - 解锁响应
struct UnlockResponse: Codable {
    let success: Bool
    let partner: User?
    let message: String

    enum CodingKeys: String, CodingKey {
        case success
        case partner
        case message
    }
}

// MARK: - 匹配代码
struct MatchCodeResponse: Codable {
    let code: String
}

struct ManualMatchRequest: Codable {
    let match_code: String
}

struct DebugUser: Codable, Identifiable {
    let id: Int
    let nickname: String
    let age: Int
    let gender: String
    let school_career: String?
    let city: String
    let contact: String
}

struct DebugUsersResponse: Codable {
    let users: [DebugUser]?
    let error: String?
}

struct DebugMatchSimulateRequest: Codable {
    let user_id: Int
    let partner_id: Int
    let status: String
    let message_count: Int
    let unlock: Bool
    let force_new: Bool?
}

struct DebugMatchSimulateResponse: Codable {
    let match: Match?
    let error: String?
}

struct ErrorMessageResponse: Codable {
    let error: String?
    let msg: String?
}

// MARK: - API响应基础类型
struct APIResponse<T: Codable>: Codable {
    let message: String?
    let error: String?
    let data: T?
}

// MARK: - 注册/登录请求
struct RegisterRequest: Codable {
    let nickname: String
    let age: Int
    let gender: String
    let school_career: String?
    let city: String
    let contact: String
}

struct UpdateProfileRequest: Codable {
    let nickname: String
    let age: Int
    let gender: String
    let school_career: String?
    let city: String
    let contact: String
}

struct LoginRequest: Codable {
    let contact: String
}

struct ReviewAccountRequest: Codable {
    let nickname: String
    let contact: String
}

struct AuthResponse: Codable {
    let message: String
    let user: User
    let access_token: String
}

struct UserResponse: Codable {
    let user: User
}

// MARK: - 购买请求
struct PurchaseRequest: Codable {
    let matches_added: Int
    let amount: Double
    let payment_method: String?
    let transaction_id: String?
}

struct PurchaseResponse: Codable {
    let message: String
    let matches_added: Int
    let matches_left: Int
}

// MARK: - 简单类型
typealias MatchesCountResponse = [String: Int]
