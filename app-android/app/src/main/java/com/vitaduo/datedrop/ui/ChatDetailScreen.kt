package com.vitaduo.datedrop.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.TagFaces
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavController
import com.vitaduo.datedrop.model.ChatMessage
import com.vitaduo.datedrop.model.RatingSubmitRequest
import com.vitaduo.datedrop.model.User
import com.vitaduo.datedrop.network.NetworkManager
import com.vitaduo.datedrop.viewmodel.AuthViewModel
import com.vitaduo.datedrop.viewmodel.ChatViewModel
import com.vitaduo.datedrop.viewmodel.MatchViewModel
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatDetailScreen(
    navController: NavController,
    matchId: Int,
    chatViewModel: ChatViewModel = viewModel(),
    authViewModel: AuthViewModel = viewModel(),
    matchViewModel: MatchViewModel = viewModel()
) {
    val appLanguageState = rememberAppLanguage()
    val appLanguage = appLanguageState.value
    val messages by chatViewModel.messages.collectAsState()
    val user by authViewModel.currentUser.collectAsState()
    val matches by matchViewModel.matches.collectAsState()
    val canCompleteChat by chatViewModel.canCompleteChat.collectAsState()
    val translatedMessages by chatViewModel.translatedMessages.collectAsState()
    val translatingMessageIds by chatViewModel.translatingMessageIds.collectAsState()
    val match = matches.find { it.id == matchId }
    
    var messageText by remember { mutableStateOf("") }
    var showEmojiPicker by remember { mutableStateOf(false) }
    var showMenu by remember { mutableStateOf(false) }
    var showReportDialog by remember { mutableStateOf(false) }
    var showBlockDialog by remember { mutableStateOf(false) }
    var reportReason by remember { mutableStateOf("") }
    val listState = rememberLazyListState()
    val emojiItems = remember {
        listOf("😀", "😂", "😍", "🥰", "😘", "😎", "🤔", "😭", "👍", "👏", "🔥", "❤️", "✨", "🎉", "💯", "🥳", "😅", "😇", "😉", "😊", "😜", "🤗", "😴", "😤", "🙌", "🙏", "💪", "🤝", "💖", "💡", "🍀", "🌟")
    }

    LaunchedEffect(matchId) {
        matchViewModel.loadMyMatches(force = false)
        matchViewModel.loadMatchDetail(matchId)
        chatViewModel.loadMessages(matchId, user?.id)
        chatViewModel.startPolling(matchId, user?.id)
    }

    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) {
            listState.animateScrollToItem(messages.size - 1)
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            chatViewModel.stopPolling()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    val displayName = match?.partnerNickname?.trim().orEmpty().ifEmpty {
                        match?.getPartnerDisplayCode(user?.id) ?: (if (appLanguage == "zh") "聊天" else "Chat")
                    }
                    val displayCode = match?.getPartnerDisplayCode(user?.id) ?: ""
                    val shouldShowCode = displayName != displayCode
                    Column {
                        Text(
                            text = displayName,
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold
                        )
                        if (shouldShowCode) {
                            Text(
                                text = displayCode,
                                fontSize = 12.sp,
                                color = Color.Gray
                            )
                        }
                        Text(
                            text = if (match?.isUnlocked == true) (if (appLanguage == "zh") "已解锁详细资料" else "Profile unlocked") else (if (appLanguage == "zh") "匿名聊天" else "Anonymous chat"),
                            fontSize = 12.sp,
                            color = if (match?.isUnlocked == true) Color.Green else Color.Gray
                        )
                    }
                },
                navigationIcon = {
                    IconButton(onClick = { navController.popBackStack() }) {
                        Icon(Icons.Default.ArrowBack, contentDescription = null)
                    }
                },
                actions = {
                    if (canCompleteChat) {
                        TextButton(onClick = { navController.navigate("rating/$matchId") }) {
                            Icon(Icons.Default.Star, contentDescription = null, tint = Color.White)
                            Spacer(modifier = Modifier.width(4.dp))
                            Text(if (appLanguage == "zh") "评价对方" else "Rate", color = Color.White)
                        }
                    } else {
                        Column(horizontalAlignment = Alignment.End) {
                            Text("${messages.size} / 20", color = Color.Gray, fontSize = 12.sp)
                            Text(if (appLanguage == "zh") "开始评分" else "Rate at 20", color = Color.Gray, fontSize = 12.sp)
                        }
                    }
                    Box {
                        IconButton(onClick = { showMenu = true }) {
                            Icon(Icons.Default.MoreVert, contentDescription = null, tint = Color.White)
                        }
                        DropdownMenu(
                            expanded = showMenu,
                            onDismissRequest = { showMenu = false }
                        ) {
                            DropdownMenuItem(
                                text = { Text(if (appLanguage == "zh") "举报用户" else "Report User") },
                                onClick = {
                                    showMenu = false
                                    showReportDialog = true
                                }
                            )
                            DropdownMenuItem(
                                text = { Text(if (appLanguage == "zh") "屏蔽用户" else "Block User") },
                                onClick = {
                                    showMenu = false
                                    showBlockDialog = true
                                }
                            )
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color(0xFF151523),
                    titleContentColor = Color.White,
                    navigationIconContentColor = Color.White
                )
            )
        },
        bottomBar = {
            Surface(
                color = Color(0xFF151523),
                tonalElevation = 8.dp
            ) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    if (showEmojiPicker) {
                        LazyVerticalGrid(
                            columns = GridCells.Fixed(8),
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(180.dp)
                                .padding(horizontal = 12.dp, vertical = 8.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            items(emojiItems) { emoji ->
                                TextButton(
                                    onClick = { messageText += emoji },
                                    contentPadding = PaddingValues(0.dp),
                                    shape = RoundedCornerShape(8.dp)
                                ) {
                                    Text(emoji, fontSize = 18.sp)
                                }
                            }
                        }
                    }
                    Row(
                        modifier = Modifier
                            .padding(16.dp)
                            .fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        IconButton(onClick = { showEmojiPicker = !showEmojiPicker }) {
                            Icon(
                                Icons.Default.TagFaces,
                                contentDescription = null,
                                tint = if (showEmojiPicker) Color.White else Color.Gray
                            )
                        }
                        TextField(
                            value = messageText,
                            onValueChange = { messageText = it },
                            modifier = Modifier.weight(1f),
                            placeholder = { Text(if (appLanguage == "zh") "输入消息..." else "Type a message...", color = Color.Gray) },
                            colors = TextFieldDefaults.textFieldColors(
                                containerColor = Color.White.copy(alpha = 0.1f),
                                focusedIndicatorColor = Color.Transparent,
                                unfocusedIndicatorColor = Color.Transparent,
                                focusedTextColor = Color.White,
                                unfocusedTextColor = Color.White
                            ),
                            shape = RoundedCornerShape(20.dp)
                        )
                        IconButton(
                            onClick = {
                                if (messageText.isNotBlank() && user != null) {
                                    chatViewModel.sendMessage(matchId, messageText, user!!.id)
                                    messageText = ""
                                    showEmojiPicker = false
                                }
                            },
                            enabled = messageText.isNotBlank()
                        ) {
                            Icon(
                                Icons.Default.Send,
                                contentDescription = null,
                                tint = if (messageText.isNotBlank()) Color.White else Color.Gray
                            )
                        }
                    }
                }
            }
        }
    ) { padding ->
        Box(modifier = Modifier.padding(padding).fillMaxSize().background(Color(0xFF0B0B12))) {
            LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                items(messages) { message ->
                    MessageBubble(
                        message = message,
                        isFromMe = message.senderId == user?.id,
                        appLanguage = appLanguage,
                        translatedText = translatedMessages[message.id],
                        isTranslating = translatingMessageIds.contains(message.id),
                        onTranslate = {
                            chatViewModel.translateMessage(message.id, message.content, appLanguage)
                        }
                    )
                }
            }
        }
    }

    if (showReportDialog) {
        AlertDialog(
            onDismissRequest = { showReportDialog = false },
            title = { Text(if (appLanguage == "zh") "举报用户" else "Report User") },
            text = {
                Column {
                    Text(if (appLanguage == "zh") "请选择举报原因：" else "Select a reason:")
                    Spacer(modifier = Modifier.height(8.dp))
                    val reasons = if (appLanguage == "zh") {
                        listOf("骚扰", "不当内容", "虚假信息", "其他")
                    } else {
                        listOf("Harassment", "Inappropriate content", "Fake profile", "Other")
                    }
                    reasons.forEach { reason ->
                        TextButton(onClick = { reportReason = reason }) {
                            Text(
                                reason,
                                color = if (reportReason == reason) Color.White else Color.Gray
                            )
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        if (reportReason.isNotBlank()) {
                            val partnerId = match?.getPartnerUserId(user?.id ?: 0) ?: return@TextButton
                            chatViewModel.reportUser(partnerId, matchId, reportReason)
                            showReportDialog = false
                            reportReason = ""
                        }
                    },
                    enabled = reportReason.isNotBlank()
                ) {
                    Text(if (appLanguage == "zh") "提交" else "Submit")
                }
            },
            dismissButton = {
                TextButton(onClick = {
                    showReportDialog = false
                    reportReason = ""
                }) {
                    Text(if (appLanguage == "zh") "取消" else "Cancel")
                }
            }
        )
    }

    if (showBlockDialog) {
        AlertDialog(
            onDismissRequest = { showBlockDialog = false },
            title = { Text(if (appLanguage == "zh") "屏蔽用户" else "Block User") },
            text = {
                Text(if (appLanguage == "zh") "确定要屏蔽该用户吗？屏蔽后将不再收到对方的消息。" else "Are you sure you want to block this user? You will no longer receive messages from them.")
            },
            confirmButton = {
                TextButton(onClick = {
                    val partnerId = match?.getPartnerUserId(user?.id ?: 0) ?: return@TextButton
                    chatViewModel.blockUser(partnerId)
                    showBlockDialog = false
                    navController.popBackStack()
                }) {
                    Text(if (appLanguage == "zh") "确定屏蔽" else "Block", color = Color.Red)
                }
            },
            dismissButton = {
                TextButton(onClick = { showBlockDialog = false }) {
                    Text(if (appLanguage == "zh") "取消" else "Cancel")
                }
            }
        )
    }
}

@Composable
fun MessageBubble(
    message: ChatMessage,
    isFromMe: Boolean,
    appLanguage: String,
    translatedText: String?,
    isTranslating: Boolean,
    onTranslate: () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = if (isFromMe) Alignment.End else Alignment.Start
    ) {
        Surface(
            color = if (isFromMe) Color.White else Color.Gray.copy(alpha = 0.2f),
            shape = RoundedCornerShape(
                topStart = 16.dp,
                topEnd = 16.dp,
                bottomStart = if (isFromMe) 16.dp else 4.dp,
                bottomEnd = if (isFromMe) 4.dp else 16.dp
            )
        ) {
            Text(
                text = message.content,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
                color = if (isFromMe) Color.Black else Color.White,
                fontSize = 16.sp
            )
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onTranslate, enabled = !isTranslating) {
                Text(
                    text = if (appLanguage == "zh") "翻译" else "Translate",
                    color = Color.Gray,
                    fontSize = 12.sp
                )
            }
            if (isTranslating) {
                CircularProgressIndicator(
                    modifier = Modifier.size(12.dp),
                    strokeWidth = 1.5.dp,
                    color = Color.Gray
                )
            }
        }
        translatedText?.let {
            Text(
                text = it,
                color = Color.Gray,
                fontSize = 13.sp,
                modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RatingScreen(
    navController: NavController,
    matchId: Int,
    authViewModel: AuthViewModel = viewModel(),
    matchViewModel: MatchViewModel = viewModel()
) {
    val appLanguageState = rememberAppLanguage()
    val appLanguage = appLanguageState.value
    val user by authViewModel.currentUser.collectAsState()
    val match by matchViewModel.selectedMatch.collectAsState()
    var selectedScore by remember { mutableStateOf<Int?>(null) }
    var isSubmitting by remember { mutableStateOf(false) }
    var showError by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf("") }
    var showUnlock by remember { mutableStateOf(false) }
    var canUnlock by remember { mutableStateOf(false) }
    var partnerProfile by remember { mutableStateOf<User?>(null) }
    var isProfileLoading by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(matchId) {
        matchViewModel.loadMatchDetail(matchId)
    }

    fun scoreDescription(score: Int): String {
        return when (score) {
            1 -> if (appLanguage == "zh") "非常不满意" else "Very dissatisfied"
            2 -> if (appLanguage == "zh") "不满意" else "Dissatisfied"
            3 -> if (appLanguage == "zh") "一般" else "Neutral"
            4 -> if (appLanguage == "zh") "满意" else "Satisfied"
            5 -> if (appLanguage == "zh") "非常满意" else "Very satisfied"
            else -> ""
        }
    }

    fun submitRating() {
        if (isSubmitting) return
        val score = selectedScore ?: return
        val userId = user?.id
        if (userId == null) {
            errorMessage = if (appLanguage == "zh") "用户信息未加载" else "User info not available"
            showError = true
            return
        }
        isSubmitting = true
        scope.launch {
            try {
                NetworkManager.api.submitRating(RatingSubmitRequest(matchId, score, userId))
                val unlockStatus = NetworkManager.api.getUnlockStatus(matchId, userId)
                canUnlock = unlockStatus.canUnlock
                showUnlock = true
                if (canUnlock) {
                    isProfileLoading = true
                    val profileResponse = NetworkManager.api.getPartnerProfile(matchId, userId)
                    partnerProfile = profileResponse.data
                    isProfileLoading = false
                }
            } catch (e: Exception) {
                errorMessage = e.message ?: if (appLanguage == "zh") "提交失败" else "Submit failed"
                showError = true
            } finally {
                isSubmitting = false
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (appLanguage == "zh") "为对方评分" else "Rate Your Match") },
                navigationIcon = {
                    IconButton(onClick = { navController.popBackStack() }) {
                        Icon(Icons.Default.ArrowBack, contentDescription = null)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color(0xFF151523),
                    titleContentColor = Color.White,
                    navigationIconContentColor = Color.White
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .background(Color(0xFF0B0B12))
                .padding(horizontal = 24.dp, vertical = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp)
        ) {
            Text(
                text = match?.partnerNickname?.ifBlank { null }
                    ?: (if (appLanguage == "zh") "匿名聊天" else "Anonymous chat"),
                fontSize = 16.sp,
                color = Color.Gray
            )
            Text(
                text = if (appLanguage == "zh") "根据聊天体验评分 (1-5星)" else "Rate based on your chat (1–5 stars)",
                fontSize = 14.sp,
                color = Color.Gray
            )
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                (1..5).forEach { score ->
                    IconButton(onClick = { selectedScore = score }) {
                        Icon(
                            Icons.Default.Star,
                            contentDescription = null,
                            tint = if ((selectedScore ?: 0) >= score) Color(0xFFFBBF24) else Color.Gray,
                            modifier = Modifier.size(40.dp)
                        )
                    }
                }
            }
            selectedScore?.let {
                Text(text = scoreDescription(it), fontSize = 16.sp, color = Color.White)
            }
            Spacer(modifier = Modifier.weight(1f))
            Button(
                onClick = { submitRating() },
                modifier = Modifier.fillMaxWidth().height(56.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (selectedScore != null) Color.White else Color.Gray.copy(alpha = 0.3f)
                ),
                shape = RoundedCornerShape(28.dp),
                enabled = selectedScore != null && !isSubmitting
            ) {
                if (isSubmitting) {
                    CircularProgressIndicator(color = Color.Black, modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                } else {
                    Text(if (appLanguage == "zh") "提交评分" else "Submit Rating", color = Color.Black, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }

    if (showError) {
        AlertDialog(
            onDismissRequest = { showError = false },
            confirmButton = {
                TextButton(onClick = { showError = false }) {
                    Text(if (appLanguage == "zh") "确定" else "OK")
                }
            },
            title = { Text(if (appLanguage == "zh") "评分失败" else "Rating Failed") },
            text = { Text(errorMessage) }
        )
    }

    if (showUnlock) {
        ModalBottomSheet(
            onDismissRequest = { showUnlock = false },
            containerColor = Color(0xFF0B0B12)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 24.dp, vertical = 20.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Icon(Icons.Default.CheckCircle, contentDescription = null, tint = Color(0xFF22C55E), modifier = Modifier.size(72.dp))
                Text(
                    text = if (appLanguage == "zh") "邀约完成" else "Rating Complete",
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
                Text(
                    text = if (canUnlock) {
                        if (appLanguage == "zh") "双方评分均达到4星以上，已解锁真实资料。" else "Both ratings are 4+ stars. Profile unlocked."
                    } else {
                        if (appLanguage == "zh") "等待双方评分达到4星后解锁资料。" else "Unlocks when both ratings reach 4+ stars."
                    },
                    fontSize = 14.sp,
                    color = Color.Gray,
                    lineHeight = 20.sp
                )
                if (canUnlock) {
                    if (isProfileLoading) {
                        CircularProgressIndicator(color = Color.White, modifier = Modifier.size(24.dp))
                    } else {
                        partnerProfile?.let { profile ->
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .background(Color.White.copy(alpha = 0.06f), RoundedCornerShape(16.dp))
                                    .padding(16.dp),
                                verticalArrangement = Arrangement.spacedBy(10.dp)
                            ) {
                                ProfileInfoRow(if (appLanguage == "zh") "昵称" else "Nickname", profile.nickname)
                                ProfileInfoRow(if (appLanguage == "zh") "年龄" else "Age", if (appLanguage == "zh") "${profile.age}岁" else "${profile.age}")
                                ProfileInfoRow(if (appLanguage == "zh") "性别" else "Gender", genderLabel(profile.gender, appLanguage))
                                ProfileInfoRow(if (appLanguage == "zh") "城市" else "City", profile.city ?: if (appLanguage == "zh") "未提供" else "Not provided")
                                profile.schoolCareer?.let { school ->
                                    ProfileInfoRow(if (appLanguage == "zh") "学校/职业" else "School/Job", school)
                                }
                                ProfileInfoRow(if (appLanguage == "zh") "联系方式" else "Contact", profile.contact ?: if (appLanguage == "zh") "未提供" else "Not provided")
                            }
                        }
                    }
                }
                Button(
                    onClick = {
                        showUnlock = false
                        navController.popBackStack("main", false)
                    },
                    modifier = Modifier.fillMaxWidth().height(52.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Color.White),
                    shape = RoundedCornerShape(26.dp)
                ) {
                    Text(if (appLanguage == "zh") "关闭" else "Close", color = Color.Black, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@Composable
fun ProfileInfoRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(text = label, color = Color.Gray, fontSize = 13.sp, modifier = Modifier.width(90.dp))
        Text(text = value, color = Color.White, fontSize = 15.sp)
    }
}

fun genderLabel(gender: String, appLanguage: String): String {
    return when (gender) {
        "male" -> if (appLanguage == "zh") "男" else "Male"
        "female" -> if (appLanguage == "zh") "女" else "Female"
        "other" -> if (appLanguage == "zh") "其他" else "Other"
        else -> gender
    }
}
