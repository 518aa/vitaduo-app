//
//  SocketManager.swift
//  DateDrop3
//
//  WebSocket管理器 - 处理实时聊天
//

import Foundation
// import Starscream  // 预留功能,暂不使用

class SocketManager {
    static let shared = SocketManager()

    // WebSocket相关 - 预留功能
    // private var socket: WebSocket?
    private var currentMatchId: Int?

    private init() {
    }

    // MARK: - 连接管理 (预留)

    func connect() {
        // TODO: 实现WebSocket连接
        print("WebSocket连接功能预留,当前使用HTTP轮询")
    }

    func disconnect() {
        // TODO: 实现WebSocket断开
        print("WebSocket断开功能预留")
    }

    // MARK: - 房间管理 (预留)

    func joinMatch(matchId: Int) {
        currentMatchId = matchId
        print("加入匹配房间: \(matchId)")
    }

    func leaveMatch(matchId: Int) {
        currentMatchId = nil
        print("离开匹配房间: \(matchId)")
    }

    // MARK: - 消息发送 (预留)

    func sendMessage(matchId: Int, message: String, userId: Int) {
        print("发送消息功能预留,使用HTTP API")
    }
}

// MARK: - 通知名称
extension Notification.Name {
    static let newMessage = Notification.Name("new_message")
    static let joinedRoom = Notification.Name("joined_room")
    static let leftRoom = Notification.Name("left_room")
}
