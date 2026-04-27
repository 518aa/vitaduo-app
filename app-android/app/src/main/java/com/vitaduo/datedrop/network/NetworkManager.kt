package com.vitaduo.datedrop.network

import android.content.Context
import android.content.SharedPreferences
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.util.Locale
import java.util.concurrent.TimeUnit

object NetworkManager {
    private const val BASE_URL = "https://dd3.tpr.wales/api/"
    private const val PREFS_NAME = "DateDropPrefs"
    private const val TOKEN_KEY = "access_token"
    private const val LANGUAGE_KEY = "app_language"

    private var prefs: SharedPreferences? = null
    private var authToken: String? = null

    fun init(context: Context) {
        if (prefs == null) {
            prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            authToken = prefs?.getString(TOKEN_KEY, null)
        }
    }

    fun saveToken(token: String) {
        authToken = token
        prefs?.edit()?.putString(TOKEN_KEY, token)?.apply()
    }

    fun clearToken() {
        authToken = null
        prefs?.edit()?.remove(TOKEN_KEY)?.apply()
    }

    fun hasToken(): Boolean = authToken != null

    fun getAppLanguage(): String {
        val defaultLang = if (Locale.getDefault().language == "zh") "zh" else "en"
        return prefs?.getString(LANGUAGE_KEY, defaultLang) ?: defaultLang
    }

    fun setAppLanguage(language: String) {
        prefs?.edit()?.putString(LANGUAGE_KEY, language)?.apply()
    }

    private val authInterceptor = Interceptor { chain ->
        val original = chain.request()
        val builder = original.newBuilder()
        authToken?.let {
            builder.header("Authorization", "Bearer $it")
        }
        chain.proceed(builder.build())
    }

    private val loggingInterceptor = HttpLoggingInterceptor().apply {
        level = HttpLoggingInterceptor.Level.BODY
    }

    private val client = OkHttpClient.Builder()
        .addInterceptor(authInterceptor)
        .addInterceptor(loggingInterceptor)
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    private val retrofit = Retrofit.Builder()
        .baseUrl(BASE_URL)
        .client(client)
        .addConverterFactory(GsonConverterFactory.create())
        .build()

    val api: ApiService = retrofit.create(ApiService::class.java)
}
