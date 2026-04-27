package com.vitaduo.datedrop.viewmodel

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.vitaduo.datedrop.model.ChatMessage
import com.vitaduo.datedrop.model.ReportRequest
import com.vitaduo.datedrop.model.BlockRequest
import com.vitaduo.datedrop.network.NetworkManager
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.*

class ChatViewModel(application: Application) : AndroidViewModel(application) {
    private val prefs = application.getSharedPreferences("DateDropPrefs", Context.MODE_PRIVATE)
    private val gson = Gson()

    private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
    val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _canCompleteChat = MutableStateFlow(false)
    val canCompleteChat: StateFlow<Boolean> = _canCompleteChat.asStateFlow()

    private val _translatedMessages = MutableStateFlow<Map<Int, String>>(emptyMap())
    val translatedMessages: StateFlow<Map<Int, String>> = _translatedMessages.asStateFlow()

    private val _translatingMessageIds = MutableStateFlow<Set<Int>>(emptySet())
    val translatingMessageIds: StateFlow<Set<Int>> = _translatingMessageIds.asStateFlow()

    private var currentMatchId: Int? = null
    private var pollingJob: Job? = null

    fun loadMessages(matchId: Int, userId: Int? = null, silent: Boolean = false) {
        currentMatchId = matchId
        if (!silent) {
            loadCachedMessages(matchId)
            _isLoading.value = _messages.value.isEmpty()
        }

        viewModelScope.launch {
            try {
                val response = NetworkManager.api.getChatMessages(matchId, userId)
                _messages.value = response.messages
                checkCanComplete()
                saveMessagesToCache(matchId, response.messages)
            } catch (e: Exception) {
                if (!silent) _errorMessage.value = e.message
            } finally {
                if (!silent) _isLoading.value = false
            }
        }
    }

    fun startPolling(matchId: Int, userId: Int? = null) {
        currentMatchId = matchId
        pollingJob?.cancel()
        pollingJob = viewModelScope.launch {
            while (true) {
                loadMessages(matchId, userId, silent = true)
                delay(5000)
            }
        }
    }

    fun stopPolling() {
        pollingJob?.cancel()
        pollingJob = null
    }

    fun sendMessage(matchId: Int, content: String, userId: Int, messageType: String = "text") {
        if (content.isBlank()) return

        viewModelScope.launch {
            try {
                val body = mapOf(
                    "match_id" to matchId,
                    "message" to content,
                    "user_id" to userId,
                    "message_type" to messageType
                )
                NetworkManager.api.sendMessage(body)
                loadMessages(matchId, userId, silent = true)
            } catch (e: Exception) {
                _errorMessage.value = e.message
            }
        }
    }

    fun translateMessage(messageId: Int, text: String, targetLanguage: String) {
        if (text.isBlank()) return
        viewModelScope.launch {
            _translatingMessageIds.value = _translatingMessageIds.value + messageId
            try {
                val response = NetworkManager.api.translate(
                    com.vitaduo.datedrop.model.TranslateRequest(text, targetLanguage)
                )
                _translatedMessages.value = _translatedMessages.value + (messageId to response.translatedText)
            } catch (e: Exception) {
                _errorMessage.value = e.message
            } finally {
                _translatingMessageIds.value = _translatingMessageIds.value - messageId
            }
        }
    }

    private fun checkCanComplete() {
        _canCompleteChat.value = _messages.value.size >= 20
    }

    private fun saveMessagesToCache(matchId: Int, messages: List<ChatMessage>) {
        val json = gson.toJson(messages)
        prefs.edit().putString("cached_messages_$matchId", json).apply()
    }

    private fun loadCachedMessages(matchId: Int) {
        val json = prefs.getString("cached_messages_$matchId", null)
        if (json != null) {
            val type = object : TypeToken<List<ChatMessage>>() {}.type
            _messages.value = gson.fromJson(json, type)
        }
    }

    fun reportUser(reportedUserId: Int, matchId: Int, reason: String) {
        viewModelScope.launch {
            try {
                NetworkManager.api.reportUser(ReportRequest(reportedUserId, matchId, reason))
                _errorMessage.value = null
            } catch (e: Exception) {
                _errorMessage.value = e.message
            }
        }
    }

    fun blockUser(blockedUserId: Int) {
        viewModelScope.launch {
            try {
                NetworkManager.api.blockUser(BlockRequest(blockedUserId))
                _errorMessage.value = null
            } catch (e: Exception) {
                _errorMessage.value = e.message
            }
        }
    }

    fun deleteMessage(messageId: Int, matchId: Int, userId: Int?) {
        viewModelScope.launch {
            try {
                NetworkManager.api.deleteMessage(messageId)
                loadMessages(matchId, userId, silent = true)
            } catch (e: Exception) {
                _errorMessage.value = e.message
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        stopPolling()
    }
}
