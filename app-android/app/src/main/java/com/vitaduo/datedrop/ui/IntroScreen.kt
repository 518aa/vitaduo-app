package com.vitaduo.datedrop.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController

@Composable
fun IntroScreen(navController: NavController) {
    val appLanguageState = rememberAppLanguage()
    val currentLanguage = appLanguageState.value
    var showResearchDialog by remember { mutableStateOf(false) }

    val researchMessage = if (currentLanguage == "zh") {
        "• 斯坦福 Marriage Pact：基于偏好问卷与算法匹配，提升长远匹配质量。\n• 价值观对齐（Value Alignment）：核心价值观一致更易形成稳定关系。\n• 相似性吸引原则：相似的兴趣、背景与目标更容易建立亲密感。\n• Big Five 人格模型：用人格维度刻画互补与协同的关系模式。\n• Gottman 关系研究：重视沟通方式与冲突处理的长期影响。"
    } else {
        "• Stanford Marriage Pact: survey-driven matching to improve long-term compatibility.\n• Value Alignment: shared core values predict relationship stability.\n• Similarity-Attraction Effect: similarity in interests and goals fosters closeness.\n• Big Five personality: captures compatibility patterns across key traits.\n• Gottman research: communication and conflict skills matter long term."
    }

    if (showResearchDialog) {
        AlertDialog(
            onDismissRequest = { showResearchDialog = false },
            title = {
                Text(if (currentLanguage == "zh") "科学依据" else "Research Foundations")
            },
            text = {
                Text(researchMessage)
            },
            confirmButton = {
                TextButton(onClick = {
                    showResearchDialog = false
                    navController.navigate("register")
                }) {
                    Text(if (currentLanguage == "zh") "继续" else "Continue")
                }
            },
            dismissButton = {
                TextButton(onClick = { showResearchDialog = false }) {
                    Text(if (currentLanguage == "zh") "取消" else "Cancel")
                }
            }
        )
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0B0B12))
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 40.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "VitaDuo",
                fontSize = 48.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )

            Spacer(modifier = Modifier.height(30.dp))

            if (currentLanguage == "zh") {
                ChineseIntroText()
            } else {
                EnglishIntroText()
            }

            Spacer(modifier = Modifier.height(30.dp))

            TextButton(onClick = {
                appLanguageState.value = if (currentLanguage == "zh") "en" else "zh"
            }) {
                Text(
                    text = if (currentLanguage == "zh") "EN" else "中文",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.Gray
                )
            }

            Spacer(modifier = Modifier.height(20.dp))

            Button(
                onClick = { showResearchDialog = true },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color.White),
                shape = RoundedCornerShape(28.dp)
            ) {
                Text(
                    text = if (currentLanguage == "zh") "开始" else "Get Started",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.Black
                )
            }
        }
    }
}

@Composable
fun ChineseIntroText() {
    Column(modifier = Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("人的一生,会遇到约2920万人。", fontSize = 17.sp, color = Color.White)
        Text("而两个陌生人价值观完全契合的概率,不足万分之一。", fontSize = 17.sp, color = Color.White)
        Text("我们不愿你错过那个'万一'。", fontSize = 17.sp, color = Color.Gray)
        Text("VitaDuo不是另一个看脸的交友软件。", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
        Text("我们相信,决定两个人能走多远的,从来不是照片有多好看,", fontSize = 15.sp, color = Color.Gray)
        Text("而是——你们如何看待世界,如何理解生活,如何在无数个平凡日夜中,成为彼此的支撑。", fontSize = 15.sp, color = Color.Gray)
        Text("66道题,找到那个与你同频的人。", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Color.White)
        Text("请真实填写,算法只负责相遇,真诚才决定未来。", fontSize = 14.sp, color = Color.Gray)
    }
}

@Composable
fun EnglishIntroText() {
    Column(modifier = Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("In a lifetime, you'll meet about 29.2 million people.", fontSize = 17.sp, color = Color.White)
        Text("But the chance that two strangers share the same core values?", fontSize = 17.sp, color = Color.White)
        Text("Less than 0.01%.", fontSize = 17.sp, color = Color.Gray)
        Text("We don't want you to miss that 'one in ten thousand.'", fontSize = 17.sp, color = Color.Gray)
        Text("VitaDuo isn't another looks-first dating app.", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
        Text("We believe what keeps two people together isn't how good they look in photos—", fontSize = 15.sp, color = Color.Gray)
        Text("It's how they see the world, how they make sense of life,", fontSize = 15.sp, color = Color.Gray)
        Text("and how they show up for each other on ordinary days.", fontSize = 15.sp, color = Color.Gray)
        Text("66 questions. One match. A lifetime of difference.", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Color.White)
        Text("Be real. The algorithm handles the rest.", fontSize = 14.sp, color = Color.Gray)
    }
}
