package com.vitaduo.datedrop.network

import com.vitaduo.datedrop.model.*
import retrofit2.Response
import retrofit2.http.*

interface ApiService {
    @POST("auth/register")
    suspend fun register(@Body request: RegisterRequest): AuthResponse

    @POST("auth/login")
    suspend fun login(@Body request: LoginRequest): AuthResponse

    @GET("auth/me")
    suspend fun getCurrentUser(): UserResponse

    @GET("questions")
    suspend fun getQuestions(@Query("lang") lang: String): QuestionsResponse

    @GET("questions/by-section")
    suspend fun getQuestionsBySection(@Query("lang") lang: String): QuestionsBySection

    @POST("answers/submit")
    suspend fun submitAnswers(@Body request: AnswerSubmitRequest): APIResponse<String>

    @GET("answers/status")
    suspend fun getAnswerStatus(): AnswerStatusResponse

    @POST("matching/generate")
    suspend fun generateMatches(@Body request: Map<String, String>): GenerateMatchesResponse

    @GET("matching/my-matches")
    suspend fun getMyMatches(): MatchesResponse

    @GET("matching/{id}")
    suspend fun getMatchDetail(@Path("id") matchId: Int): APIResponse<Match>

    @POST("matching/{id}/start-chat")
    suspend fun startChat(@Path("id") matchId: Int): APIResponse<Match>

    @GET("chat/{id}/messages")
    suspend fun getChatMessages(
        @Path("id") matchId: Int,
        @Query("user_id") userId: Int? = null
    ): MessagesResponse

    @POST("chat/send")
    suspend fun sendMessage(@Body body: Map<String, @JvmSuppressWildcards Any>): APIResponse<ChatMessage>

    @GET("users/profile")
    suspend fun getProfile(): APIResponse<User>

    @PUT("users/profile")
    suspend fun updateProfile(@Body request: UpdateProfileRequest): UserResponse

    @DELETE("users/delete")
    suspend fun deleteAccount(): APIResponse<String>

    @GET("users/matches-count")
    suspend fun getMatchesCount(): Map<String, Int>

    @POST("users/purchase-matches")
    suspend fun purchaseMatches(@Body request: PurchaseRequest): PurchaseResponse

    @GET("users/match-code")
    suspend fun getMatchCode(): MatchCodeResponse

    @POST("matching/manual-by-code")
    suspend fun manualMatchByCode(@Body request: Map<String, String>): APIResponse<Match>

    @POST("translate")
    suspend fun translate(@Body request: TranslateRequest): TranslateResponse

    @POST("ratings/submit")
    suspend fun submitRating(@Body request: RatingSubmitRequest): APIResponse<Rating>

    @GET("ratings/status/{matchId}")
    suspend fun getRatingStatus(@Path("matchId") matchId: Int): RatingStatusResponse

    @GET("matching/{matchId}/unlock-status")
    suspend fun getUnlockStatus(
        @Path("matchId") matchId: Int,
        @Query("user_id") userId: Int? = null
    ): UnlockStatusResponse

    @GET("matching/{matchId}/partner-profile")
    suspend fun getPartnerProfile(
        @Path("matchId") matchId: Int,
        @Query("user_id") userId: Int? = null
    ): APIResponse<User>

    @POST("users/report")
    suspend fun reportUser(@Body request: ReportRequest): APIResponse<String>

    @POST("users/block")
    suspend fun blockUser(@Body request: BlockRequest): APIResponse<String>

    @DELETE("chat/messages/{messageId}")
    suspend fun deleteMessage(@Path("messageId") messageId: Int): APIResponse<String>
}
