//
//  AuthViewModel.swift
//  DateDrop3
//
//  认证视图模型
//

import Foundation
import Combine

class AuthViewModel: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var isQuestionnaireCompleted = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()
    private let networkManager = NetworkManager.shared
    private let questionnaireCompletedKey = "questionnaire_completed"
    private var appLanguage: String {
        UserDefaults.standard.string(forKey: "app_language") ?? "en"
    }

    init() {
        loadUserFromCache()
    }

    // MARK: - 注册

    func register(nickname: String, age: Int, gender: String, schoolCareer: String?, city: String?, contact: String?) {
        isLoading = true
        errorMessage = nil

        let request = RegisterRequest(
            nickname: nickname,
            age: age,
            gender: gender,
            school_career: schoolCareer,
            city: city ?? "",
            contact: contact ?? ""
        )

        networkManager.register(user: request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case let .failure(error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] response in
                    self?.currentUser = response.user
                    self?.saveToken(response.access_token)
                    self?.saveUser(response.user)
                    self?.isAuthenticated = true
                    self?.updateQuestionnaireCompleted(false)
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - 登录

    func login(contact: String) {
        isLoading = true
        errorMessage = nil

        networkManager.login(contact: contact)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case let .failure(error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] response in
                    self?.currentUser = response.user
                    self?.saveToken(response.access_token)
                    self?.saveUser(response.user)
                    self?.checkQuestionnaireStatus()
                }
            )
            .store(in: &cancellables)
    }

    func reviewLogin(nickname: String, contact: String) {
        isLoading = true
        errorMessage = nil

        networkManager.reviewAccount(nickname: nickname, contact: contact)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure = completion {
                        return
                    }
                },
                receiveValue: { [weak self] response in
                    self?.currentUser = response.user
                    self?.saveToken(response.access_token)
                    self?.saveUser(response.user)
                    self?.updateQuestionnaireCompleted(true)
                    self?.isAuthenticated = true
                }
            )
            .store(in: &cancellables)
    }

    func updateProfile(nickname: String, age: Int, gender: String, schoolCareer: String?, city: String, contact: String) {
        isLoading = true
        errorMessage = nil

        let request = UpdateProfileRequest(
            nickname: nickname,
            age: age,
            gender: gender,
            school_career: schoolCareer,
            city: city,
            contact: contact
        )

        networkManager.updateProfile(request: request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case let .failure(error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] response in
                    self?.currentUser = response.user
                    self?.saveUser(response.user)
                }
            )
            .store(in: &cancellables)
    }

    func deleteAccount(completion: @escaping (Result<Void, Error>) -> Void) {
        isLoading = true
        errorMessage = nil
        networkManager.deleteAccount()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] result in
                    self?.isLoading = false
                    if case let .failure(error) = result {
                        self?.errorMessage = error.localizedDescription
                        completion(.failure(error))
                    }
                },
                receiveValue: { [weak self] _ in
                    self?.logout()
                    completion(.success(()))
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - 登出

    func logout() {
        currentUser = nil
        isAuthenticated = false
        isQuestionnaireCompleted = false
        NetworkManager.shared.clearToken()
        UserDefaults.standard.removeObject(forKey: "saved_user")
        UserDefaults.standard.removeObject(forKey: questionnaireCompletedKey)
        SocketManager.shared.disconnect()
    }

    // MARK: - 获取当前用户

    func fetchCurrentUser() {
        networkManager.getCurrentUser()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] response in
                    self?.currentUser = response.user
                    self?.checkQuestionnaireStatus()
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - 问卷状态检查

    func checkQuestionnaireStatus() {
        networkManager.getAnswerStatus()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case let .failure(error) = completion {
                        if self?.appLanguage == "zh" {
                            self?.errorMessage = "检查问卷状态失败: \(error.localizedDescription)"
                        } else {
                            self?.errorMessage = "Failed to check questionnaire status: \(error.localizedDescription)"
                        }
                        self?.isAuthenticated = true
                    }
                },
                receiveValue: { [weak self] response in
                    self?.updateQuestionnaireCompleted(response.completed)
                    self?.isAuthenticated = true
                }
            )
            .store(in: &cancellables)
    }

    func updateQuestionnaireCompleted(_ completed: Bool) {
        isQuestionnaireCompleted = completed
        saveQuestionnaireCompleted(completed)
    }
    // MARK: - 私有方法

    private func saveToken(_ token: String) {
        NetworkManager.shared.saveToken(token)
    }

    private func saveUser(_ user: User) {
        if let encoded = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(encoded, forKey: "saved_user")
        }
    }

    private func saveQuestionnaireCompleted(_ completed: Bool) {
        UserDefaults.standard.set(completed, forKey: questionnaireCompletedKey)
    }

    private func loadQuestionnaireCompleted() -> Bool? {
        if UserDefaults.standard.object(forKey: questionnaireCompletedKey) == nil {
            return nil
        }
        return UserDefaults.standard.bool(forKey: questionnaireCompletedKey)
    }

    private func loadUserFromCache() {
        if let data = UserDefaults.standard.data(forKey: "saved_user"),
           let user = try? JSONDecoder().decode(User.self, from: data) {
            self.currentUser = user
            if let cachedCompleted = loadQuestionnaireCompleted() {
                self.isQuestionnaireCompleted = cachedCompleted
            }
            if NetworkManager.shared.hasToken() {
                // Check questionnaire status first before confirming authentication
                self.checkQuestionnaireStatus()
            }
        }
    }
}
