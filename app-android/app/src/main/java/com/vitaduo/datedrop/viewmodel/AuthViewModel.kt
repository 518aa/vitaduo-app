package com.vitaduo.datedrop.viewmodel

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.vitaduo.datedrop.model.AuthResponse
import com.vitaduo.datedrop.model.RegisterRequest
import com.vitaduo.datedrop.model.UpdateProfileRequest
import com.vitaduo.datedrop.model.User
import com.vitaduo.datedrop.network.NetworkManager
import com.google.gson.Gson
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class AuthViewModel(application: Application) : AndroidViewModel(application) {
    private val prefs = application.getSharedPreferences("DateDropPrefs", Context.MODE_PRIVATE)
    private val gson = Gson()

    private val _currentUser = MutableStateFlow<User?>(null)
    val currentUser: StateFlow<User?> = _currentUser.asStateFlow()

    private val _isAuthenticated = MutableStateFlow(false)
    val isAuthenticated: StateFlow<Boolean> = _isAuthenticated.asStateFlow()

    private val _isQuestionnaireCompleted = MutableStateFlow(false)
    val isQuestionnaireCompleted: StateFlow<Boolean> = _isQuestionnaireCompleted.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _matchCode = MutableStateFlow<String?>(null)
    val matchCode: StateFlow<String?> = _matchCode.asStateFlow()

    private val _matchCodeLoading = MutableStateFlow(false)
    val matchCodeLoading: StateFlow<Boolean> = _matchCodeLoading.asStateFlow()

    private val _matchCodeError = MutableStateFlow<String?>(null)
    val matchCodeError: StateFlow<String?> = _matchCodeError.asStateFlow()

    private val _profileUpdating = MutableStateFlow(false)
    val profileUpdating: StateFlow<Boolean> = _profileUpdating.asStateFlow()

    private val _deleteAccountLoading = MutableStateFlow(false)
    val deleteAccountLoading: StateFlow<Boolean> = _deleteAccountLoading.asStateFlow()

    init {
        loadUserFromCache()
    }

    fun register(nickname: String, age: Int, gender: String, schoolCareer: String?, city: String?, contact: String?) {
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            try {
                val request = RegisterRequest(nickname, age, gender, schoolCareer, city, contact)
                val response = NetworkManager.api.register(request)
                handleAuthResponse(response)
            } catch (e: Exception) {
                _errorMessage.value = e.message
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun login(contact: String) {
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            try {
                val response = NetworkManager.api.login(com.vitaduo.datedrop.model.LoginRequest(contact))
                handleAuthResponse(response)
            } catch (e: Exception) {
                _errorMessage.value = e.message
            } finally {
                _isLoading.value = false
            }
        }
    }

    private fun handleAuthResponse(response: AuthResponse) {
        _currentUser.value = response.user
        NetworkManager.saveToken(response.accessToken)
        saveUserToCache(response.user)
        checkQuestionnaireStatus()
    }

    fun checkQuestionnaireStatus() {
        viewModelScope.launch {
            try {
                val status = NetworkManager.api.getAnswerStatus()
                _isQuestionnaireCompleted.value = status.completed
                prefs.edit().putBoolean("questionnaire_completed", status.completed).apply()
                _isAuthenticated.value = true
            } catch (e: Exception) {
                _errorMessage.value = e.message
                _isAuthenticated.value = true // Even if status check fails, we are authenticated
            }
        }
    }

    fun updateQuestionnaireCompleted(completed: Boolean) {
        _isQuestionnaireCompleted.value = completed
        prefs.edit().putBoolean("questionnaire_completed", completed).apply()
    }

    fun fetchCurrentUser() {
        viewModelScope.launch {
            try {
                val response = NetworkManager.api.getCurrentUser()
                _currentUser.value = response.user
                checkQuestionnaireStatus()
            } catch (e: Exception) {
                _errorMessage.value = e.message
            }
        }
    }

    fun updateProfile(nickname: String, age: Int, gender: String, schoolCareer: String?, city: String?, contact: String?) {
        viewModelScope.launch {
            _profileUpdating.value = true
            _errorMessage.value = null
            try {
                val request = UpdateProfileRequest(nickname, age, gender, schoolCareer, city, contact)
                val response = NetworkManager.api.updateProfile(request)
                _currentUser.value = response.user
                saveUserToCache(response.user)
            } catch (e: Exception) {
                _errorMessage.value = e.message
            } finally {
                _profileUpdating.value = false
            }
        }
    }

    fun deleteAccount() {
        viewModelScope.launch {
            _deleteAccountLoading.value = true
            _errorMessage.value = null
            try {
                NetworkManager.api.deleteAccount()
                logout()
            } catch (e: Exception) {
                _errorMessage.value = e.message
            } finally {
                _deleteAccountLoading.value = false
            }
        }
    }

    fun loadMatchCode(forceRefresh: Boolean = false) {
        viewModelScope.launch {
            val cache = loadMatchCodeCache()
            if (!forceRefresh && cache != null && isMatchCodeCacheFresh(cache)) {
                _matchCode.value = cache.code
                _matchCodeLoading.value = false
                return@launch
            }
            _matchCodeLoading.value = true
            _matchCodeError.value = null
            try {
                val response = NetworkManager.api.getMatchCode()
                _matchCode.value = response.code
                saveMatchCodeCache(response.code)
            } catch (e: Exception) {
                _matchCodeError.value = e.message
            } finally {
                _matchCodeLoading.value = false
            }
        }
    }

    fun logout() {
        _currentUser.value = null
        _isAuthenticated.value = false
        _isQuestionnaireCompleted.value = false
        NetworkManager.clearToken()
        prefs.edit().remove("saved_user").remove("questionnaire_completed").apply()
    }

    private fun saveUserToCache(user: User) {
        val json = gson.toJson(user)
        prefs.edit().putString("saved_user", json).apply()
    }

    private fun loadUserFromCache() {
        val json = prefs.getString("saved_user", null)
        if (json != null) {
            _currentUser.value = gson.fromJson(json, User::class.java)
            _isQuestionnaireCompleted.value = prefs.getBoolean("questionnaire_completed", false)
            if (NetworkManager.hasToken()) {
                checkQuestionnaireStatus()
            }
        }
    }

    private fun saveMatchCodeCache(code: String) {
        val cache = MatchCodeCache(code = code, updatedAt = System.currentTimeMillis())
        prefs.edit().putString("match_code_cache", gson.toJson(cache)).apply()
    }

    private fun loadMatchCodeCache(): MatchCodeCache? {
        val json = prefs.getString("match_code_cache", null) ?: return null
        return gson.fromJson(json, MatchCodeCache::class.java)
    }

    private fun isMatchCodeCacheFresh(cache: MatchCodeCache): Boolean {
        val ttl = 24 * 60 * 60 * 1000L
        return System.currentTimeMillis() - cache.updatedAt < ttl
    }
}

data class MatchCodeCache(
    val code: String,
    val updatedAt: Long
)
