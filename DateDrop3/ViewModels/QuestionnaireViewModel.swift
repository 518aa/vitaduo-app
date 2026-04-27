//
//  QuestionnaireViewModel.swift
//  DateDrop3
//
//  问卷视图模型
//

import Foundation
import Combine

class QuestionnaireViewModel: ObservableObject {
    @Published var questions: [Question] = []
    @Published var sections: [String: [Question]] = [:]
    @Published var answers: [Int: Int] = [:]  // question_id: answer
    @Published var isLoading = false
    @Published var isSubmitting = false
    @Published var loadErrorMessage: String?
    @Published var submitErrorMessage: String?
    @Published var submitSuccess = false
    @Published var answerStatus: AnswerStatusResponse?

    private let sectionOrder = ["core_values", "lifestyle", "political", "relationship", "personality", "communication"]
    private let sectionNames = [
        "core_values": "核心价值观",
        "lifestyle": "生活方式",
        "political": "政治观点",
        "relationship": "关系期望",
        "personality": "性格特质",
        "communication": "沟通模式"
    ]
    private let sectionNamesEn = [
        "core_values": "Core Values",
        "lifestyle": "Lifestyle",
        "political": "Politics",
        "relationship": "Relationship",
        "personality": "Personality",
        "communication": "Communication"
    ]

    private var cancellables = Set<AnyCancellable>()
    private let networkManager = NetworkManager.shared
    private let questionsCacheKeyPrefix = "cached_questions_sections_"
    private let questionsCacheTTL: TimeInterval = 60 * 60 * 24
    private let answerStatusCacheKey = "cached_answer_status"
    private let answerStatusCacheTTL: TimeInterval = 60 * 5

    private struct QuestionsCache: Codable {
        let questions: [Question]
        let sections: [String: [Question]]
        let updatedAt: TimeInterval
    }

    private struct AnswerStatusCache: Codable {
        let status: AnswerStatusResponse
        let updatedAt: TimeInterval
    }

    static func clearAnswerStatusCache() {
        UserDefaults.standard.removeObject(forKey: "cached_answer_status")
    }

    private var appLanguage: String {
        UserDefaults.standard.string(forKey: "app_language") ?? "en"
    }

    // MARK: - 加载问卷

    func loadQuestions(lang: String = "en") {
        loadErrorMessage = nil

        if let cache = loadQuestionsCache(lang: lang) {
            questions = cache.questions
            sections = cache.sections
            isLoading = false
            if isQuestionsCacheFresh(cache) {
                return
            }
        } else {
            isLoading = true
        }
        
        networkManager.getQuestionsBySection(lang: lang)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case let .failure(error) = completion {
                        self?.loadQuestionsFallback(lang: lang, originalError: error)
                    }
                },
                receiveValue: { [weak self] response in
                    guard let self = self else { return }
                    self.isLoading = false
                    // 动态合并所有 section 下的题目
                    let combined = response.sections.values.flatMap { $0 }
                    self.questions = combined
                    self.sections = response.sections
                    self.saveQuestionsCache(lang: lang, questions: combined, sections: response.sections)
                }
            )
            .store(in: &cancellables)
    }
    
    private func loadQuestionsFallback(lang: String, originalError: Error) {
        networkManager.getQuestions(lang: lang)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self = self else { return }
                    self.isLoading = false
                    if case let .failure(error) = completion {
                        if self.appLanguage == "zh" {
                            self.loadErrorMessage = "加载题目失败: \(originalError.localizedDescription); 备用接口错误: \(error.localizedDescription)"
                        } else {
                            self.loadErrorMessage = "Failed to load questions: \(originalError.localizedDescription); fallback error: \(error.localizedDescription)"
                        }
                    }
                },
                receiveValue: { [weak self] response in
                    guard let self = self else { return }
                    self.loadErrorMessage = nil
                    self.questions = response.questions
                    // 尝试按 section 分组, 没有则归类到 unknown
                    let grouped = Dictionary(grouping: response.questions, by: { $0.section ?? "unknown" })
                    self.sections = grouped
                    self.saveQuestionsCache(lang: lang, questions: response.questions, sections: grouped)
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - 答案管理

    func setAnswer(questionId: Int, answer: Int) {
        answers[questionId] = answer
    }

    func getAnswer(questionId: Int) -> Int? {
        return answers[questionId]
    }

    func getProgress() -> (answered: Int, total: Int) {
        let answered = answers.count
        return (answered, 66)
    }

    func isQuestionAnswered(questionId: Int) -> Bool {
        return answers[questionId] != nil
    }

    func getSectionProgress(section: String) -> (answered: Int, total: Int) {
        guard let sectionQuestions = sections[section] else {
            return (0, 0)
        }

        let answered = sectionQuestions.filter { isQuestionAnswered(questionId: $0.id) }.count
        return (answered, sectionQuestions.count)
    }

    // MARK: - 提交答案

    func submitAnswers() {
        isSubmitting = true
        submitErrorMessage = nil
        submitSuccess = false

        // 验证是否全部答完
        if answers.count != 66 {
            submitErrorMessage = appLanguage == "zh" ? "请完成全部66道题目" : "Please complete all 66 questions"
            isSubmitting = false
            return
        }

        // 构建答案数组
        let answerArray: [Answer] = answers.map { questionId, answer in
            Answer(question_id: questionId, answer: answer)
        }.sorted { $0.question_id < $1.question_id }

        networkManager.submitAnswers(answers: answerArray)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isSubmitting = false
                    if case let .failure(error) = completion {
                        self?.submitErrorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] response in
                    self?.submitSuccess = true
                    self?.submitErrorMessage = nil
                    self?.loadAnswerStatus(force: true)
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - 答案状态

    func loadAnswerStatus(force: Bool = false) {
        if !force, let cache = loadAnswerStatusCache(), isAnswerStatusCacheFresh(cache) {
            answerStatus = cache.status
            return
        }
        networkManager.getAnswerStatus()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] status in
                    self?.answerStatus = status
                    self?.saveAnswerStatusCache(status)
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - 辅助方法

    func getSectionName(_ section: String) -> String {
        if appLanguage == "zh" {
            return sectionNames[section] ?? section
        }
        return sectionNamesEn[section] ?? section
    }

    func getSectionOrder() -> [String] {
        return sectionOrder
    }

    func getQuestionsForSection(_ section: String) -> [Question] {
        return sections[section] ?? []
    }

    private func saveQuestionsCache(lang: String, questions: [Question], sections: [String: [Question]]) {
        let cache = QuestionsCache(questions: questions, sections: sections, updatedAt: Date().timeIntervalSince1970)
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: questionsCacheKeyPrefix + lang)
        }
    }

    private func loadQuestionsCache(lang: String) -> QuestionsCache? {
        guard let data = UserDefaults.standard.data(forKey: questionsCacheKeyPrefix + lang) else {
            return nil
        }
        return try? JSONDecoder().decode(QuestionsCache.self, from: data)
    }

    private func isQuestionsCacheFresh(_ cache: QuestionsCache) -> Bool {
        Date().timeIntervalSince1970 - cache.updatedAt < questionsCacheTTL
    }

    private func saveAnswerStatusCache(_ status: AnswerStatusResponse) {
        let cache = AnswerStatusCache(status: status, updatedAt: Date().timeIntervalSince1970)
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: answerStatusCacheKey)
        }
    }

    private func loadAnswerStatusCache() -> AnswerStatusCache? {
        guard let data = UserDefaults.standard.data(forKey: answerStatusCacheKey) else {
            return nil
        }
        return try? JSONDecoder().decode(AnswerStatusCache.self, from: data)
    }

    private func isAnswerStatusCacheFresh(_ cache: AnswerStatusCache) -> Bool {
        Date().timeIntervalSince1970 - cache.updatedAt < answerStatusCacheTTL
    }
}
