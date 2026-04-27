package com.vitaduo.datedrop.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
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
import com.vitaduo.datedrop.viewmodel.MatchViewModel
import java.util.UUID

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaywallScreen(navController: NavController, matchViewModel: MatchViewModel = viewModel()) {
    val appLanguageState = rememberAppLanguage()
    val appLanguage = appLanguageState.value
    val purchaseLoading by matchViewModel.purchaseLoading.collectAsState()
    val errorMessage by matchViewModel.errorMessage.collectAsState()
    val matchesLeft by matchViewModel.matchesLeft.collectAsState()
    val packages = remember {
        listOf(
            PaywallPackage(
                id = "matches_3",
                titleZh = "3次匹配",
                titleEn = "3 Matches",
                amount = 18.0,
                priceZh = "¥18",
                priceEn = "$2.49",
                matchesAdded = 3
            ),
            PaywallPackage(
                id = "matches_10",
                titleZh = "10次匹配 · 推荐",
                titleEn = "10 Matches · Recommended",
                amount = 48.0,
                priceZh = "¥48",
                priceEn = "$6.99",
                matchesAdded = 10,
                isRecommended = true
            ),
            PaywallPackage(
                id = "matches_unlimited",
                titleZh = "无限次",
                titleEn = "Unlimited",
                amount = 98.0,
                priceZh = "¥98",
                priceEn = "$12.99",
                matchesAdded = 999,
                isUnlimited = true
            )
        )
    }
    var selectedPackage by remember { mutableStateOf<PaywallPackage?>(null) }
    var showSuccess by remember { mutableStateOf(false) }
    var showError by remember { mutableStateOf(false) }
    var errorText by remember { mutableStateOf("") }
    var didAttemptPurchase by remember { mutableStateOf(false) }
    var showRestoreResult by remember { mutableStateOf(false) }
    var restoreRequested by remember { mutableStateOf(false) }
    val serviceUnavailable = true

    LaunchedEffect(purchaseLoading, errorMessage, didAttemptPurchase) {
        if (!purchaseLoading && didAttemptPurchase) {
            if (errorMessage != null) {
                errorText = errorMessage ?: ""
                showError = true
            } else {
                showSuccess = true
            }
            didAttemptPurchase = false
        }
    }

    LaunchedEffect(matchesLeft, restoreRequested) {
        if (restoreRequested) {
            showRestoreResult = true
            restoreRequested = false
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (appLanguage == "zh") "购买次数" else "Buy Matches") },
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
                .verticalScroll(rememberScrollState())
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp)
        ) {
            Text(
                text = if (appLanguage == "zh") "增加匹配次数" else "Get More Matches",
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )

            if (serviceUnavailable) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color.White.copy(alpha = 0.08f), RoundedCornerShape(16.dp))
                        .padding(16.dp)
                ) {
                    Text(
                        text = if (appLanguage == "zh") "购买服务暂未开放" else "Purchase service is not available yet",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White
                    )
                    Text(
                        text = if (appLanguage == "zh") "开放后会第一时间提示" else "We will notify you when it becomes available",
                        fontSize = 13.sp,
                        color = Color.Gray
                    )
                }
            }

            Text(
                text = if (appLanguage == "zh") "为了维持服务器运行并提供更好的匹配服务，我们需要您的支持。" else "To keep the service running and improve matching, we need your support.",
                fontSize = 16.sp,
                color = Color.Gray,
                lineHeight = 24.sp
            )

            packages.forEach { pkg ->
                PricingCard(
                    title = if (appLanguage == "zh") pkg.titleZh else pkg.titleEn,
                    priceZh = pkg.priceZh,
                    priceEn = pkg.priceEn,
                    selected = selectedPackage?.id == pkg.id,
                    recommended = pkg.isRecommended,
                    enabled = !serviceUnavailable,
                    onClick = { selectedPackage = pkg }
                )
            }

            Button(
                onClick = {
                    val pkg = selectedPackage ?: return@Button
                    matchViewModel.clearError()
                    didAttemptPurchase = true
                    matchViewModel.purchaseMatches(
                        matchesAdded = pkg.matchesAdded,
                        amount = pkg.amount,
                        paymentMethod = "manual",
                        transactionId = UUID.randomUUID().toString()
                    )
                },
                modifier = Modifier.fillMaxWidth().height(56.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color.White,
                    disabledContainerColor = Color.White.copy(alpha = 0.4f)
                ),
                shape = RoundedCornerShape(28.dp),
                enabled = selectedPackage != null && !purchaseLoading && !serviceUnavailable
            ) {
                if (purchaseLoading) {
                    CircularProgressIndicator(color = Color.Black, modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                } else {
                    Text(if (appLanguage == "zh") "确认购买" else "Purchase", color = Color.Black, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
                }
            }

            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Button(
                    onClick = {
                        restoreRequested = true
                        matchViewModel.loadMatchesCount()
                    },
                    modifier = Modifier.fillMaxWidth().height(52.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color.White.copy(alpha = 0.12f),
                        disabledContainerColor = Color.White.copy(alpha = 0.08f)
                    ),
                    shape = RoundedCornerShape(26.dp),
                    enabled = !purchaseLoading && !serviceUnavailable
                ) {
                    Text(if (appLanguage == "zh") "恢复购买" else "Restore Purchases", color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Medium)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.CheckCircle, contentDescription = null, tint = Color(0xFF22C55E))
                    Text(
                        text = if (appLanguage == "zh") "安全支付由平台处理" else "Secure payment by platform",
                        fontSize = 14.sp,
                        color = Color.Gray
                    )
                }
                TextButton(onClick = { navController.navigate("terms") }) {
                    Text(
                        text = if (appLanguage == "zh") "条款与隐私政策" else "Terms & Privacy",
                        fontSize = 14.sp,
                        color = Color.Gray
                    )
                }
                Text(
                    text = if (appLanguage == "zh") "购买记录可在应用商店账户设置中查看" else "Purchase history is available in store settings",
                    fontSize = 12.sp,
                    color = Color.Gray.copy(alpha = 0.7f)
                )
            }
        }
    }

    if (showSuccess) {
        AlertDialog(
            onDismissRequest = { showSuccess = false },
            confirmButton = {
                TextButton(onClick = {
                    showSuccess = false
                    navController.popBackStack()
                }) {
                    Text(if (appLanguage == "zh") "开始使用" else "Start Using")
                }
            },
            title = { Text(if (appLanguage == "zh") "购买成功" else "Purchase Successful") },
            text = {
                Text(
                    if (appLanguage == "zh")
                        "已成功购买：${selectedPackage?.titleZh.orEmpty()}"
                    else
                        "Successfully purchased: ${selectedPackage?.titleEn.orEmpty()}"
                )
            }
        )
    }

    if (showError) {
        AlertDialog(
            onDismissRequest = { showError = false },
            confirmButton = {
                TextButton(onClick = { showError = false }) {
                    Text(if (appLanguage == "zh") "重试" else "Retry")
                }
            },
            title = { Text(if (appLanguage == "zh") "购买失败" else "Purchase Failed") },
            text = { Text(errorText) }
        )
    }

    if (showRestoreResult) {
        AlertDialog(
            onDismissRequest = { showRestoreResult = false },
            confirmButton = {
                TextButton(onClick = { showRestoreResult = false }) {
                    Text(if (appLanguage == "zh") "好的" else "OK")
                }
            },
            title = { Text(if (appLanguage == "zh") "恢复购买" else "Restore Purchases") },
            text = {
                Text(
                    if (appLanguage == "zh")
                        "已尝试恢复购买，当前剩余次数：$matchesLeft"
                    else
                        "Restore attempted. Remaining matches: $matchesLeft"
                )
            }
        )
    }
}

@Composable
fun PricingCard(title: String, priceZh: String, priceEn: String, selected: Boolean, recommended: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val appLanguageState = rememberAppLanguage()
    val appLanguage = appLanguageState.value
    Surface(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        enabled = enabled,
        color = if (selected) Color.White else Color.White.copy(alpha = if (enabled) 0.1f else 0.04f),
        shape = RoundedCornerShape(16.dp)
    ) {
        Row(
            modifier = Modifier.padding(20.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    text = title,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (selected) Color.Black else Color.White.copy(alpha = if (enabled) 1f else 0.5f)
                )
                if (recommended) {
                    Text(
                        text = if (appLanguage == "zh") "性价比最高" else "Best value",
                        fontSize = 12.sp,
                        color = if (selected) Color.Black.copy(alpha = 0.7f) else Color.Gray.copy(alpha = if (enabled) 1f else 0.5f)
                    )
                }
            }
            Text(
                text = if (appLanguage == "zh") priceZh else priceEn,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = if (selected) Color.Black else Color.White.copy(alpha = if (enabled) 1f else 0.5f)
            )
        }
    }
}

data class PaywallPackage(
    val id: String,
    val titleZh: String,
    val titleEn: String,
    val amount: Double,
    val priceZh: String,
    val priceEn: String,
    val matchesAdded: Int,
    val isRecommended: Boolean = false,
    val isUnlimited: Boolean = false
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TermsScreen(navController: NavController) {
    val appLanguageState = rememberAppLanguage()
    val appLanguage = appLanguageState.value

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (appLanguage == "zh") "条款与隐私政策" else "Terms & Privacy") },
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
                .verticalScroll(rememberScrollState())
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    text = if (appLanguage == "zh") "服务条款" else "Terms of Service",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
                Text(
                    text = if (appLanguage == "zh")
                        "• 购买套餐后，匹配次数将立即添加到您的账户\n• 匹配次数不可退款，除非出现技术故障\n• 我们保留随时修改套餐价格的权利\n• 滥用服务可能导致账户暂停"
                    else
                        "• Match credits are added immediately after purchase\n• Credits are non-refundable except in case of technical failure\n• We reserve the right to modify package prices\n• Service abuse may result in account suspension",
                    fontSize = 14.sp,
                    color = Color.Gray,
                    lineHeight = 20.sp
                )
            }

            Divider(color = Color.White.copy(alpha = 0.2f))

            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    text = if (appLanguage == "zh") "隐私政策" else "Privacy Policy",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
                Text(
                    text = if (appLanguage == "zh")
                        "• 我们尊重您的隐私，不会共享您的个人信息\n• 购买信息仅由平台处理，我们不会存储支付细节\n• 使用数据仅用于改善服务质量"
                    else
                        "• We respect your privacy and never share your personal information\n• Payment data is handled by the platform only; we don't store payment details\n• Usage data is used solely to improve service quality",
                    fontSize = 14.sp,
                    color = Color.Gray,
                    lineHeight = 20.sp
                )
            }

            Divider(color = Color.White.copy(alpha = 0.2f))

            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    text = if (appLanguage == "zh") "退款政策" else "Refund Policy",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
                Text(
                    text = if (appLanguage == "zh")
                        "• 如遇技术问题导致购买失败，请联系客服\n• 我们会在5个工作日内处理退款请求\n• 平台的退款政策同样适用于本应用"
                    else
                        "• Contact support if technical issues cause purchase failure\n• Refund requests are processed within 5 business days\n• The platform refund policy also applies to this app",
                    fontSize = 14.sp,
                    color = Color.Gray,
                    lineHeight = 20.sp
                )
            }
        }
    }
}
