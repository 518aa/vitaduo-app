package com.vitaduo.datedrop.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Person2
import androidx.compose.material.icons.filled.ChatBubble
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
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
import com.vitaduo.datedrop.model.Match
import com.vitaduo.datedrop.viewmodel.AuthViewModel
import com.vitaduo.datedrop.viewmodel.MatchViewModel

@Composable
fun MainScreen(navController: NavController, authViewModel: AuthViewModel = viewModel()) {
    var selectedTab by remember { mutableStateOf(0) }
    val appLanguageState = rememberAppLanguage()
    val appLanguage = appLanguageState.value

    Scaffold(
        bottomBar = {
            NavigationBar(
                containerColor = Color(0xFF151523),
                contentColor = Color.White
            ) {
                NavigationBarItem(
                    selected = selectedTab == 0,
                    onClick = { selectedTab = 0 },
                    icon = { Icon(Icons.Default.Person2, contentDescription = null) },
                    label = { Text(if (appLanguage == "zh") "匹配" else "Matches") },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = Color.White,
                        unselectedIconColor = Color.Gray,
                        selectedTextColor = Color.White,
                        unselectedTextColor = Color.Gray,
                        indicatorColor = Color(0xFF9333EA)
                    )
                )
                NavigationBarItem(
                    selected = selectedTab == 1,
                    onClick = { selectedTab = 1 },
                    icon = { Icon(Icons.Default.ChatBubble, contentDescription = null) },
                    label = { Text(if (appLanguage == "zh") "聊天" else "Chats") },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = Color.White,
                        unselectedIconColor = Color.Gray,
                        selectedTextColor = Color.White,
                        unselectedTextColor = Color.Gray,
                        indicatorColor = Color(0xFF9333EA)
                    )
                )
                NavigationBarItem(
                    selected = selectedTab == 2,
                    onClick = { selectedTab = 2 },
                    icon = { Icon(Icons.Default.Person, contentDescription = null) },
                    label = { Text(if (appLanguage == "zh") "我的" else "Me") },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = Color.White,
                        unselectedIconColor = Color.Gray,
                        selectedTextColor = Color.White,
                        unselectedTextColor = Color.Gray,
                        indicatorColor = Color(0xFF9333EA)
                    )
                )
            }
        }
    ) { padding ->
        Box(modifier = Modifier.padding(padding).fillMaxSize().background(Color(0xFF0B0B12))) {
            when (selectedTab) {
                0 -> MatchTab(navController)
                1 -> ChatTab(navController)
                2 -> ProfileTab(navController)
            }
        }
    }
}

@Composable
fun MatchTab(navController: NavController, viewModel: MatchViewModel = viewModel()) {
    val appLanguageState = rememberAppLanguage()
    val appLanguage = appLanguageState.value
    val matches by viewModel.matches.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val isGenerating by viewModel.isGenerating.collectAsState()
    val matchesLeft by viewModel.matchesLeft.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()
    val didGenerateMatch by viewModel.didGenerateMatch.collectAsState()
    var showMatchPrompt by remember { mutableStateOf(false) }
    var showNoMatchAlert by remember { mutableStateOf(false) }
    val noMatchMessage = if (appLanguage == "zh") "根据算法，暂未匹配到合适的对象，请随后再试。" else "No suitable match found for now. Please try again later."

    LaunchedEffect(Unit) {
        viewModel.loadMyMatches()
    }

    LaunchedEffect(didGenerateMatch) {
        if (didGenerateMatch) {
            showMatchPrompt = true
            viewModel.consumeDidGenerateMatch()
        }
    }

    LaunchedEffect(errorMessage) {
        if (errorMessage == noMatchMessage) {
            showNoMatchAlert = true
            viewModel.clearError()
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(24.dp)
    ) {
        Text(
            text = if (appLanguage == "zh") "匹配对象" else "Matches",
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White
        )

        Text(
            text = if (appLanguage == "zh") 
                "本应用基于用户价值观问卷答案的相似和互补性，通过算法为每个用户推荐同频的匹配对象。" 
                else "We recommend compatible matches using questionnaire similarity and complementarity.",
            fontSize = 15.sp,
            color = Color.Gray,
            lineHeight = 22.sp
        )

        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(text = if (appLanguage == "zh") "剩余次数:" else "Remaining:", fontSize = 14.sp, color = Color.Gray)
            Surface(
                color = Color.White.copy(alpha = 0.1f),
                shape = RoundedCornerShape(8.dp),
                onClick = { navController.navigate("paywall") }
            ) {
                Text(
                    text = "$matchesLeft",
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                    color = Color.White,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }

        Button(
            onClick = {
                if (matchesLeft > 0) {
                    viewModel.generateMatches()
                } else {
                    navController.navigate("paywall")
                }
            },
            modifier = Modifier.fillMaxWidth().height(56.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = Color.White,
                disabledContainerColor = Color.Gray.copy(alpha = 0.3f)
            ),
            shape = RoundedCornerShape(28.dp),
            enabled = matchesLeft > 0 && !isGenerating
        ) {
            if (isGenerating) {
                CircularProgressIndicator(color = Color.Black, modifier = Modifier.size(24.dp))
            } else {
                Text(text = if (appLanguage == "zh") "开始匹配" else "Start Matching", color = Color.Black, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
            }
        }

        if (isLoading && matches.isEmpty()) {
            CircularProgressIndicator(color = Color.White)
        }

        matches.firstOrNull()?.let { match ->
            MatchCard(match, navController, viewModel)
        } ?: run {
            Text(text = if (appLanguage == "zh") "点击开始匹配获取对象" else "Tap Start Matching to get a match", color = Color.Gray, fontSize = 16.sp)
        }

        errorMessage?.let {
            Text(text = it, color = Color.Red, fontSize = 14.sp)
        }
    }

    if (showMatchPrompt) {
        AlertDialog(
            onDismissRequest = { showMatchPrompt = false },
            confirmButton = {
                TextButton(onClick = { showMatchPrompt = false }) {
                    Text(if (appLanguage == "zh") "知道了" else "OK")
                }
            },
            title = { Text(if (appLanguage == "zh") "已为您匹配一位伴侣" else "A match is ready") },
            text = {
                Text(
                    if (appLanguage == "zh")
                        "请点击开始聊天按钮进行初步交往，如果双方的评价都在四星以上，系统会解锁您的个人资料和联系方式，否则您的个人资料将始终处于保密状态。"
                    else
                        "Tap Start Chat to begin. If both ratings are four stars or higher, the system unlocks real profiles and contact info; otherwise, your profile remains private."
                )
            }
        )
    }

    if (showNoMatchAlert) {
        AlertDialog(
            onDismissRequest = { showNoMatchAlert = false },
            confirmButton = {
                TextButton(onClick = { showNoMatchAlert = false }) {
                    Text(if (appLanguage == "zh") "知道了" else "OK")
                }
            },
            title = { Text(if (appLanguage == "zh") "暂未匹配到对象" else "No match yet") },
            text = { Text(noMatchMessage) }
        )
    }
}

@Composable
fun MatchCard(match: Match, navController: NavController, viewModel: MatchViewModel) {
    val appLanguageState = rememberAppLanguage()
    val appLanguage = appLanguageState.value
    val authViewModel: AuthViewModel = viewModel()
    val user by authViewModel.currentUser.collectAsState()
    val displayName = match.partnerNickname?.trim().orEmpty().ifEmpty {
        match.getPartnerDisplayCode(user?.id)
    }
    val displayCode = match.getPartnerDisplayCode(user?.id)
    val shouldShowCode = displayName != displayCode
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color.Gray.copy(alpha = 0.1f), RoundedCornerShape(16.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(text = if (appLanguage == "zh") "热聊中" else "Hot Chat", color = Color(0xFFFB923C), fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
        
        Text(text = displayName.ifEmpty { if (appLanguage == "zh") "匹配对象" else "Partner" }, color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Bold)
        if (shouldShowCode) {
            Text(text = displayCode, color = Color.Gray, fontSize = 12.sp, fontWeight = FontWeight.Medium)
        }
        
        match.aiIntro?.let {
            Text(text = it, color = Color.Gray, fontSize = 14.sp, lineHeight = 20.sp)
        }

        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(text = if (appLanguage == "zh") "匹配度" else "Match", color = Color.Gray, fontSize = 14.sp)
            Spacer(modifier = Modifier.weight(1f))
            Text(text = "${match.similarityScore.toInt()}%", color = Color.Green, fontSize = 20.sp, fontWeight = FontWeight.Bold)
        }

        Button(
            onClick = { 
                viewModel.startChat(match.id)
                navController.navigate("chat/${match.id}")
            },
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(containerColor = Color.White),
            shape = RoundedCornerShape(12.dp)
        ) {
            Icon(Icons.Default.ChatBubble, contentDescription = null, tint = Color.Black)
            Spacer(modifier = Modifier.width(8.dp))
            Text(text = if (appLanguage == "zh") "开始聊天" else "Start Chat", color = Color.Black)
        }
    }
}

@Composable
fun ChatTab(navController: NavController, viewModel: MatchViewModel = viewModel()) {
    val appLanguageState = rememberAppLanguage()
    val appLanguage = appLanguageState.value
    val matches by viewModel.matches.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()

    LaunchedEffect(Unit) {
        viewModel.loadMyMatches(force = true)
    }

    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(text = if (appLanguage == "zh") "列表" else "Chats", fontSize = 28.sp, fontWeight = FontWeight.Bold, color = Color.White)
            IconButton(onClick = { viewModel.loadMyMatches(force = true) }) {
                Icon(Icons.Default.Refresh, contentDescription = null, tint = Color.White)
            }
        }

        if (matches.isEmpty()) {
            Box(modifier = Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                if (isLoading) {
                    CircularProgressIndicator(color = Color.White)
                } else {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(text = if (appLanguage == "zh") "暂无聊天记录" else "No chats yet", color = Color.Gray)
                        Spacer(modifier = Modifier.height(12.dp))
                        Text(text = if (appLanguage == "zh") "前往匹配页面开始聊天" else "Go to Matches to start chatting", color = Color.Gray)
                    }
                }
            }
        } else {
            LazyColumn(
                modifier = Modifier.weight(1f).fillMaxWidth(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                items(matches) { match ->
                    ChatListItem(match, navController)
                }
            }
        }
    }
}

@Composable
fun ChatListItem(match: Match, navController: NavController) {
    val appLanguageState = rememberAppLanguage()
    val appLanguage = appLanguageState.value
    val authViewModel: AuthViewModel = viewModel()
    val user by authViewModel.currentUser.collectAsState()
    val displayName = match.partnerNickname?.trim().orEmpty().ifEmpty {
        match.getPartnerDisplayCode(user?.id)
    }
    val displayCode = match.getPartnerDisplayCode(user?.id)
    val shouldShowCode = displayName != displayCode
    Surface(
        onClick = { navController.navigate("chat/${match.id}") },
        color = Color.Gray.copy(alpha = 0.1f),
        shape = RoundedCornerShape(16.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(text = displayName, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            if (shouldShowCode) {
                Text(text = displayCode, color = Color.Gray, fontSize = 12.sp)
            }
            Row {
                Text(text = if (appLanguage == "zh") "匹配度" else "Match", color = Color.Gray, fontSize = 14.sp)
                Spacer(modifier = Modifier.weight(1f))
                Text(text = "${match.similarityScore.toInt()}%", color = Color.Green, fontSize = 18.sp, fontWeight = FontWeight.Bold)
            }
            match.unreadCount?.takeIf { it > 0 }?.let {
                Text(
                    text = if (appLanguage == "zh") "未读 $it" else "$it unread",
                    color = Color(0xFFFB7185),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}

@Composable
fun ProfileTab(navController: NavController, authViewModel: AuthViewModel = viewModel(), matchViewModel: MatchViewModel = viewModel()) {
    val appLanguageState = rememberAppLanguage()
    val appLanguage = appLanguageState.value
    val user by authViewModel.currentUser.collectAsState()
    val matchCode by authViewModel.matchCode.collectAsState()
    val matchCodeLoading by authViewModel.matchCodeLoading.collectAsState()
    val matchCodeError by authViewModel.matchCodeError.collectAsState()
    val manualMatchLoading by matchViewModel.manualMatchLoading.collectAsState()
    val deleteAccountLoading by authViewModel.deleteAccountLoading.collectAsState()
    var showManualMatchDialog by remember { mutableStateOf(false) }
    var manualMatchCode by remember { mutableStateOf("") }
    var showAdvancedSettingsDialog by remember { mutableStateOf(false) }
    var showRetakeDialog by remember { mutableStateOf(false) }
    var showDeleteImpactDialog by remember { mutableStateOf(false) }
    var showDeleteConfirmDialog by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        authViewModel.loadMatchCode()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(text = if (appLanguage == "zh") "我的" else "Me", fontSize = 28.sp, fontWeight = FontWeight.Bold, color = Color.White)

        user?.let { u ->
            ProfileCard(u, navController)
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(Color.White.copy(alpha = 0.08f), RoundedCornerShape(16.dp))
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(text = if (appLanguage == "zh") "你的匹配码" else "Your match code", color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            if (matchCodeLoading) {
                CircularProgressIndicator(color = Color.White, modifier = Modifier.size(20.dp))
            } else {
                Text(text = matchCode ?: "--", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            }
            matchCodeError?.let { Text(text = it, color = Color.Red, fontSize = 12.sp) }
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(Color.White.copy(alpha = 0.08f), RoundedCornerShape(16.dp))
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(text = if (appLanguage == "zh") "语言" else "Language", color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(
                    onClick = { appLanguageState.value = "zh" },
                    colors = ButtonDefaults.buttonColors(containerColor = if (appLanguage == "zh") Color.White else Color.White.copy(alpha = 0.12f)),
                    shape = RoundedCornerShape(14.dp)
                ) {
                    Text("中文", color = if (appLanguage == "zh") Color.Black else Color.White)
                }
                Button(
                    onClick = { appLanguageState.value = "en" },
                    colors = ButtonDefaults.buttonColors(containerColor = if (appLanguage == "en") Color.White else Color.White.copy(alpha = 0.12f)),
                    shape = RoundedCornerShape(14.dp)
                ) {
                    Text("English", color = if (appLanguage == "en") Color.Black else Color.White)
                }
            }
        }

        SettingsItem(if (appLanguage == "zh") "重新填写问卷" else "Retake Questionnaire") {
            showRetakeDialog = true
        }
        SettingsItem(if (appLanguage == "zh") "手动匹配" else "Manual Match") {
            showManualMatchDialog = true
        }
        SettingsItem(if (appLanguage == "zh") "高级设置" else "Advanced Settings") {
            showAdvancedSettingsDialog = true
        }
        SettingsItem(if (appLanguage == "zh") "隐私与免责条款" else "Privacy & Disclaimer") {}
        SettingsItem(if (appLanguage == "zh") "关于App" else "About App") {}
        
        Button(
            onClick = { 
                authViewModel.logout()
                navController.navigate("intro") {
                    popUpTo(0)
                }
            },
            modifier = Modifier.fillMaxWidth().height(50.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color.Red.copy(alpha = 0.2f)),
            shape = RoundedCornerShape(14.dp)
        ) {
            Text(text = if (appLanguage == "zh") "退出登录" else "Logout", color = Color.White)
        }

        Button(
            onClick = { showDeleteImpactDialog = true },
            modifier = Modifier.fillMaxWidth().height(50.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color.Red.copy(alpha = 0.4f)),
            shape = RoundedCornerShape(14.dp),
            enabled = !deleteAccountLoading
        ) {
            if (deleteAccountLoading) {
                CircularProgressIndicator(color = Color.White, modifier = Modifier.size(20.dp))
            } else {
                Text(text = if (appLanguage == "zh") "删除账号" else "Delete Account", color = Color.White)
            }
        }
    }

    if (showManualMatchDialog) {
        AlertDialog(
            onDismissRequest = { showManualMatchDialog = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        if (manualMatchCode.isNotBlank()) {
                            matchViewModel.manualMatchByCode(manualMatchCode.trim())
                            showManualMatchDialog = false
                            manualMatchCode = ""
                        }
                    },
                    enabled = !manualMatchLoading
                ) {
                    Text(if (appLanguage == "zh") "确认" else "Confirm")
                }
            },
            dismissButton = {
                TextButton(onClick = { showManualMatchDialog = false }) {
                    Text(if (appLanguage == "zh") "取消" else "Cancel")
                }
            },
            title = { Text(if (appLanguage == "zh") "手动匹配" else "Manual Match") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(if (appLanguage == "zh") "输入匹配码" else "Enter match code")
                    TextField(
                        value = manualMatchCode,
                        onValueChange = { manualMatchCode = it },
                        placeholder = { Text(if (appLanguage == "zh") "示例：A7F3C2 或 #A7F3C2" else "Example: A7F3C2 or #A7F3C2") }
                    )
                }
            }
        )
    }

    if (showAdvancedSettingsDialog) {
        AlertDialog(
            onDismissRequest = { showAdvancedSettingsDialog = false },
            confirmButton = {
                TextButton(onClick = { showAdvancedSettingsDialog = false }) {
                    Text(if (appLanguage == "zh") "知道了" else "OK")
                }
            },
            title = { Text(if (appLanguage == "zh") "高级设置" else "Advanced Settings") },
            text = { Text(if (appLanguage == "zh") "该功能暂未开放" else "This feature is not available yet.") }
        )
    }

    if (showRetakeDialog) {
        AlertDialog(
            onDismissRequest = { showRetakeDialog = false },
            confirmButton = {
                TextButton(onClick = {
                    showRetakeDialog = false
                    authViewModel.updateQuestionnaireCompleted(false)
                    navController.navigate("questionnaire")
                }) {
                    Text(if (appLanguage == "zh") "确认" else "Confirm")
                }
            },
            dismissButton = {
                TextButton(onClick = { showRetakeDialog = false }) {
                    Text(if (appLanguage == "zh") "取消" else "Cancel")
                }
            },
            title = { Text(if (appLanguage == "zh") "重新填写问卷" else "Retake Questionnaire") },
            text = { Text(if (appLanguage == "zh") "重新填写会覆盖现有答案，是否继续？" else "Retaking will overwrite existing answers. Continue?") }
        )
    }

    if (showDeleteImpactDialog) {
        AlertDialog(
            onDismissRequest = { showDeleteImpactDialog = false },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteImpactDialog = false
                    showDeleteConfirmDialog = true
                }) {
                    Text(if (appLanguage == "zh") "继续注销" else "Continue")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteImpactDialog = false }) {
                    Text(if (appLanguage == "zh") "取消" else "Cancel")
                }
            },
            title = { Text(if (appLanguage == "zh") "注销账号前请了解影响" else "Before You Delete Your Account") },
            text = {
                Text(
                    if (appLanguage == "zh")
                        "删除账号后，你的资料、问卷答案与聊天记录将被永久移除，且无法恢复。"
                    else
                        "Deleting your account permanently removes your profile, answers, and chat history."
                )
            }
        )
    }

    if (showDeleteConfirmDialog) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirmDialog = false },
            confirmButton = {
                TextButton(onClick = {
                    authViewModel.deleteAccount()
                    showDeleteConfirmDialog = false
                }) {
                    Text(if (appLanguage == "zh") "确认删除" else "Delete")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirmDialog = false }) {
                    Text(if (appLanguage == "zh") "取消" else "Cancel")
                }
            },
            title = { Text(if (appLanguage == "zh") "删除账号" else "Delete Account") },
            text = { Text(if (appLanguage == "zh") "删除后无法恢复，确定要继续吗？" else "This action cannot be undone. Continue?") }
        )
    }
}

@Composable
fun ProfileCard(user: com.vitaduo.datedrop.model.User, navController: NavController) {
    val appLanguageState = rememberAppLanguage()
    val appLanguage = appLanguageState.value
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color.White.copy(alpha = 0.1f), RoundedCornerShape(16.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(text = user.nickname, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
            Spacer(modifier = Modifier.weight(1f))
            TextButton(onClick = { navController.navigate("profile") }) {
                Text(
                    text = if (appLanguage == "zh") "编辑" else "Edit",
                    color = Color.White,
                    fontSize = 14.sp
                )
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Tag("${user.age}${if (appLanguage == "zh") "岁" else " yrs"}")
            Tag(if (user.gender == "male") (if (appLanguage == "zh") "男" else "Male") else (if (appLanguage == "zh") "女" else "Female"))
            user.city?.let { Tag(it) }
        }
    }
}

@Composable
fun Tag(text: String) {
    Text(
        text = text,
        modifier = Modifier.background(Color.White.copy(alpha = 0.12f), RoundedCornerShape(10.dp)).padding(horizontal = 10.dp, vertical = 4.dp),
        color = Color.White,
        fontSize = 14.sp
    )
}

@Composable
fun SettingsItem(title: String, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        color = Color.White.copy(alpha = 0.08f),
        shape = RoundedCornerShape(14.dp)
    ) {
        Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(text = title, color = Color.White, fontSize = 16.sp)
            Spacer(modifier = Modifier.weight(1f))
            Icon(Icons.Default.Settings, contentDescription = null, tint = Color.Gray)
        }
    }
}
