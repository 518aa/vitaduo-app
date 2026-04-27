package com.vitaduo.datedrop.viewmodel

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.vitaduo.datedrop.model.Match
import com.vitaduo.datedrop.network.NetworkManager
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class MatchViewModel(application: Application) : AndroidViewModel(application) {
    private val prefs = application.getSharedPreferences("DateDropPrefs", Context.MODE_PRIVATE)
    private val gson = Gson()

    private val _matches = MutableStateFlow<List<Match>>(emptyList())
    val matches: StateFlow<List<Match>> = _matches.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _isGenerating = MutableStateFlow(false)
    val isGenerating: StateFlow<Boolean> = _isGenerating.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _matchesLeft = MutableStateFlow(0)
    val matchesLeft: StateFlow<Int> = _matchesLeft.asStateFlow()

    private val _generateSuccess = MutableStateFlow(false)
    val generateSuccess: StateFlow<Boolean> = _generateSuccess.asStateFlow()

    private val _didGenerateMatch = MutableStateFlow(false)
    val didGenerateMatch: StateFlow<Boolean> = _didGenerateMatch.asStateFlow()

    private val _manualMatchLoading = MutableStateFlow(false)
    val manualMatchLoading: StateFlow<Boolean> = _manualMatchLoading.asStateFlow()

    private val _purchaseLoading = MutableStateFlow(false)
    val purchaseLoading: StateFlow<Boolean> = _purchaseLoading.asStateFlow()

    private val _selectedMatch = MutableStateFlow<Match?>(null)
    val selectedMatch: StateFlow<Match?> = _selectedMatch.asStateFlow()

    init {
        loadCachedMatches()
        loadMatchesCount()
    }

    fun loadMyMatches(force: Boolean = false) {
        viewModelScope.launch {
            if (!force && _matches.value.isNotEmpty()) return@launch
            
            _isLoading.value = true
            _errorMessage.value = null
            try {
                val response = NetworkManager.api.getMyMatches()
                _matches.value = response.matches
                saveMatchesToCache(response.matches)
            } catch (e: Exception) {
                _errorMessage.value = e.message
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun generateMatches() {
        viewModelScope.launch {
            _isGenerating.value = true
            _errorMessage.value = null
            _generateSuccess.value = false
            _didGenerateMatch.value = false
            try {
                val response = NetworkManager.api.generateMatches(mapOf("lang" to getAppLanguage()))
                _matches.value = response.matches
                _matchesLeft.value = response.matchesLeft
                _generateSuccess.value = true
                _didGenerateMatch.value = response.matches.isNotEmpty()
                saveMatchesToCache(response.matches)
            } catch (e: Exception) {
                _errorMessage.value = e.message
                loadMatchesCount()
            } finally {
                _isGenerating.value = false
            }
        }
    }

    fun loadMatchesCount() {
        viewModelScope.launch {
            try {
                val response = NetworkManager.api.getMatchesCount()
                _matchesLeft.value = response["matches_left"] ?: 0
            } catch (e: Exception) {
                // Ignore
            }
        }
    }

    fun consumeDidGenerateMatch() {
        _didGenerateMatch.value = false
    }

    fun clearError() {
        _errorMessage.value = null
    }

    fun startChat(matchId: Int) {
        viewModelScope.launch {
            try {
                NetworkManager.api.startChat(matchId)
                loadMyMatches(force = true)
            } catch (e: Exception) {
                _errorMessage.value = e.message
            }
        }
    }

    fun manualMatchByCode(code: String) {
        viewModelScope.launch {
            _manualMatchLoading.value = true
            _errorMessage.value = null
            try {
                val response = NetworkManager.api.manualMatchByCode(mapOf("code" to code))
                response.data?.let { match ->
                    _matches.value = listOf(match)
                    _didGenerateMatch.value = true
                    saveMatchesToCache(_matches.value)
                }
            } catch (e: Exception) {
                _errorMessage.value = e.message
            } finally {
                _manualMatchLoading.value = false
            }
        }
    }

    fun purchaseMatches(matchesAdded: Int, amount: Double, paymentMethod: String, transactionId: String) {
        viewModelScope.launch {
            _purchaseLoading.value = true
            _errorMessage.value = null
            try {
                val response = NetworkManager.api.purchaseMatches(
                    com.vitaduo.datedrop.model.PurchaseRequest(
                        matchesAdded = matchesAdded,
                        amount = amount,
                        paymentMethod = paymentMethod,
                        transactionId = transactionId
                    )
                )
                _matchesLeft.value = response.matchesLeft
            } catch (e: Exception) {
                _errorMessage.value = e.message
            } finally {
                _purchaseLoading.value = false
            }
        }
    }

    fun loadMatchDetail(matchId: Int) {
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            try {
                val response = NetworkManager.api.getMatchDetail(matchId)
                _selectedMatch.value = response.data
            } catch (e: Exception) {
                _errorMessage.value = e.message
            } finally {
                _isLoading.value = false
            }
        }
    }

    private fun saveMatchesToCache(matches: List<Match>) {
        val json = gson.toJson(matches)
        prefs.edit().putString("cached_matches", json).apply()
    }

    private fun loadCachedMatches() {
        val json = prefs.getString("cached_matches", null)
        if (json != null) {
            val type = object : TypeToken<List<Match>>() {}.type
            _matches.value = gson.fromJson(json, type)
        }
    }

    private fun getAppLanguage(): String {
        return NetworkManager.getAppLanguage()
    }
}
