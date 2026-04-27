package com.vitaduo.datedrop.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.vitaduo.datedrop.model.Answer
import com.vitaduo.datedrop.model.AnswerSubmitRequest
import com.vitaduo.datedrop.model.Question
import com.vitaduo.datedrop.model.AnswerStatusResponse
import com.vitaduo.datedrop.network.NetworkManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.Locale

class QuestionnaireViewModel : ViewModel() {
    private val _questions = MutableStateFlow<List<Question>>(emptyList())
    val questions: StateFlow<List<Question>> = _questions.asStateFlow()

    private val _sections = MutableStateFlow<Map<String, List<Question>>>(emptyMap())
    val sections: StateFlow<Map<String, List<Question>>> = _sections.asStateFlow()

    private val _answers = MutableStateFlow<Map<Int, Int>>(emptyMap())
    val answers: StateFlow<Map<Int, Int>> = _answers.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _isSubmitting = MutableStateFlow(false)
    val isSubmitting: StateFlow<Boolean> = _isSubmitting.asStateFlow()

    private val _loadErrorMessage = MutableStateFlow<String?>(null)
    val loadErrorMessage: StateFlow<String?> = _loadErrorMessage.asStateFlow()

    private val _submitErrorMessage = MutableStateFlow<String?>(null)
    val submitErrorMessage: StateFlow<String?> = _submitErrorMessage.asStateFlow()

    private val _submitSuccess = MutableStateFlow(false)
    val submitSuccess: StateFlow<Boolean> = _submitSuccess.asStateFlow()

    private val sectionOrder = listOf("core_values", "lifestyle", "political", "relationship", "personality", "communication")
    private val sectionNames = mapOf(
        "core_values" to "核心价值观",
        "lifestyle" to "生活方式",
        "political" to "政治观点",
        "relationship" to "关系期望",
        "personality" to "性格特质",
        "communication" to "沟通模式"
    )
    private val sectionNamesEn = mapOf(
        "core_values" to "Core Values",
        "lifestyle" to "Lifestyle",
        "political" to "Politics",
        "relationship" to "Relationship",
        "personality" to "Personality",
        "communication" to "Communication"
    )

    fun loadQuestions() {
        val lang = NetworkManager.getAppLanguage()
        viewModelScope.launch {
            _isLoading.value = true
            _loadErrorMessage.value = null
            try {
                val response = NetworkManager.api.getQuestionsBySection(lang)
                val sectionMap = response.sections ?: response.data?.sections ?: emptyMap()
                _sections.value = sectionMap
                _questions.value = sectionMap.values.flatten()
            } catch (e: Exception) {
                loadQuestionsFallback(lang, e.message)
            } finally {
                _isLoading.value = false
            }
        }
    }

    private suspend fun loadQuestionsFallback(lang: String, originalError: String?) {
        try {
            val response = NetworkManager.api.getQuestions(lang)
            _questions.value = response.questions
            _sections.value = response.questions.groupBy { it.section ?: "unknown" }
        } catch (e: Exception) {
            _loadErrorMessage.value = "Failed to load questions: $originalError; Fallback error: ${e.message}"
        }
    }

    fun setAnswer(questionId: Int, answer: Int) {
        val currentAnswers = _answers.value.toMutableMap()
        currentAnswers[questionId] = answer
        _answers.value = currentAnswers
    }

    fun submitAnswers() {
        val appLanguage = NetworkManager.getAppLanguage()
        if (_answers.value.size != 66) {
            _submitErrorMessage.value = if (appLanguage == "zh") "请完成全部66道题目" else "Please complete all 66 questions"
            return
        }

        viewModelScope.launch {
            _isSubmitting.value = true
            _submitErrorMessage.value = null
            _submitSuccess.value = false
            try {
                val answerList = _answers.value.map { Answer(it.key, it.value) }.sortedBy { it.questionId }
                NetworkManager.api.submitAnswers(AnswerSubmitRequest(answerList))
                _submitSuccess.value = true
            } catch (e: Exception) {
                _submitErrorMessage.value = e.message
            } finally {
                _isSubmitting.value = false
            }
        }
    }

    fun getSectionName(section: String): String {
        val appLanguage = NetworkManager.getAppLanguage()
        return if (appLanguage == "zh") sectionNames[section] ?: section else sectionNamesEn[section] ?: section
    }

    fun clearLoadError() {
        _loadErrorMessage.value = null
    }

    fun clearSubmitError() {
        _submitErrorMessage.value = null
    }

    fun getSectionOrder() = sectionOrder

    fun getProgress(): Pair<Int, Int> {
        return _answers.value.size to 66
    }
}
