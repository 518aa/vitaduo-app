package com.vitaduo.datedrop.model

import com.google.gson.annotations.SerializedName

data class User(
    val id: Int,
    val nickname: String,
    val age: Int,
    val gender: String,
    @SerializedName("school_career") val schoolCareer: String?,
    val city: String?,
    val contact: String?,
    @SerializedName("avatar_url") val avatarUrl: String?,
    @SerializedName("matches_left") var matchesLeft: Int,
    @SerializedName("is_verified") val isVerified: Boolean,
    @SerializedName("created_at") val createdAt: String?
)

data class Question(
    val id: Int,
    val text: String,
    @SerializedName("is_likert") val isLikert: Boolean,
    @SerializedName("is_sensitive") val isSensitive: Boolean,
    val section: String?,
    val weight: Double?
)

data class QuestionsResponse(
    val questions: List<Question>,
    val total: Int
)

data class QuestionsBySection(
    val sections: Map<String, List<Question>>? = null,
    val data: SectionsData? = null
)

data class SectionsData(
    val sections: Map<String, List<Question>>
)

data class Answer(
    @SerializedName("question_id") val questionId: Int,
    val answer: Int
)

data class AnswerSubmitRequest(
    val answers: List<Answer>
)

data class AnswerStatusResponse(
    val completed: Boolean,
    @SerializedName("answered_count") val answeredCount: Int,
    val total: Int
)

data class Match(
    val id: Int,
    @SerializedName("user1_id") val user1Id: Int,
    @SerializedName("user2_id") val user2Id: Int,
    @SerializedName("similarity_score") val similarityScore: Double,
    val status: String,
    @SerializedName("is_unlocked") val isUnlocked: Boolean,
    @SerializedName("chat_message_count") val chatMessageCount: Int,
    @SerializedName("created_at") val createdAt: String?,
    @SerializedName("last_message_at") val lastMessageAt: String?,
    @SerializedName("last_message_sender_id") val lastMessageSenderId: Int?,
    @SerializedName("unread_count") val unreadCount: Int?,
    @SerializedName("ai_intro") val aiIntro: String?,
    @SerializedName("partner_nickname") val partnerNickname: String?
) {
    fun getPartnerUserId(currentUserId: Int): Int {
        return if (user1Id == currentUserId) user2Id else user1Id
    }

    fun getPartnerDisplayCode(currentUserId: Int?): String {
        val seed = currentUserId?.let { getPartnerUserId(it) } ?: id
        return formatCode(seed)
    }

    private fun formatCode(seed: Int): String {
        val chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".toCharArray()
        var value = (seed.toULong() and 0xffffffffu) + 0x9E3779B97F4A7C15u
        val builder = StringBuilder()
        repeat(5) {
            value = value xor (value shr 12)
            value = value xor (value shl 25)
            value = value xor (value shr 27)
            val index = (value % chars.size.toULong()).toInt()
            builder.append(chars[index])
        }
        return "U-$builder"
    }
}

data class MatchesResponse(
    val matches: List<Match>,
    val total: Int
)

data class GenerateMatchesResponse(
    val message: String,
    val matches: List<Match>,
    @SerializedName("matches_left") val matchesLeft: Int
)

data class ChatMessage(
    val id: Int,
    @SerializedName("match_id") val matchId: Int,
    @SerializedName("sender_id") val senderId: Int,
    val content: String,
    @SerializedName("message_type") val messageType: String,
    @SerializedName("is_read") val isRead: Boolean,
    @SerializedName("created_at") val createdAt: String?
)

data class MessagesResponse(
    val messages: List<ChatMessage>,
    val total: Int
)

data class APIResponse<T>(
    val message: String?,
    val error: String?,
    val data: T?
)

data class RegisterRequest(
    val nickname: String,
    val age: Int,
    val gender: String,
    @SerializedName("school_career") val schoolCareer: String?,
    val city: String?,
    val contact: String?
)

data class LoginRequest(
    val contact: String
)

data class AuthResponse(
    val message: String,
    val user: User,
    @SerializedName("access_token") val accessToken: String
)

data class UserResponse(
    val user: User
)

data class UpdateProfileRequest(
    val nickname: String,
    val age: Int,
    val gender: String,
    @SerializedName("school_career") val schoolCareer: String?,
    val city: String?,
    val contact: String?
)

data class MatchCodeResponse(
    val code: String
)

data class PurchaseRequest(
    @SerializedName("matches_added") val matchesAdded: Int,
    val amount: Double,
    @SerializedName("payment_method") val paymentMethod: String,
    @SerializedName("transaction_id") val transactionId: String
)

data class PurchaseResponse(
    val message: String,
    @SerializedName("matches_added") val matchesAdded: Int,
    @SerializedName("matches_left") val matchesLeft: Int
)

data class TranslateRequest(
    val text: String,
    @SerializedName("target_language") val targetLanguage: String
)

data class TranslateResponse(
    @SerializedName("translated_text") val translatedText: String,
    @SerializedName("target_language") val targetLanguage: String
)

data class RatingSubmitRequest(
    @SerializedName("match_id") val matchId: Int,
    val score: Int,
    @SerializedName("user_id") val userId: Int?
)

data class Rating(
    val id: Int,
    @SerializedName("match_id") val matchId: Int,
    @SerializedName("rater_id") val raterId: Int,
    @SerializedName("rated_user_id") val ratedUserId: Int,
    val score: Int,
    @SerializedName("created_at") val createdAt: String?
)

data class RatingStatusResponse(
    @SerializedName("match_id") val matchId: Int,
    @SerializedName("both_rated") val bothRated: Boolean,
    @SerializedName("is_unlocked") val isUnlocked: Boolean,
    @SerializedName("ratings_count") val ratingsCount: Int
)

data class UnlockStatusResponse(
    @SerializedName("match_id") val matchId: Int,
    @SerializedName("can_unlock") val canUnlock: Boolean,
    val reason: String,
    @SerializedName("is_unlocked") val isUnlocked: Boolean
)

data class ReportRequest(
    @SerializedName("reported_user_id") val reportedUserId: Int,
    @SerializedName("match_id") val matchId: Int,
    val reason: String
)

data class BlockRequest(
    @SerializedName("blocked_user_id") val blockedUserId: Int
)
