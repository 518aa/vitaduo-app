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
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavController
import com.vitaduo.datedrop.model.Question
import com.vitaduo.datedrop.viewmodel.AuthViewModel
import com.vitaduo.datedrop.viewmodel.QuestionnaireViewModel

@Composable
fun QuestionnaireScreen(
    navController: NavController,
    viewModel: QuestionnaireViewModel = viewModel(),
    authViewModel: AuthViewModel = viewModel()
) {
    val appLanguageState = rememberAppLanguage()
    val appLanguage = appLanguageState.value
    val questions by viewModel.questions.collectAsState()
    val answers by viewModel.answers.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val isSubmitting by viewModel.isSubmitting.collectAsState()
    val loadErrorMessage by viewModel.loadErrorMessage.collectAsState()
    val submitErrorMessage by viewModel.submitErrorMessage.collectAsState()
    val submitSuccess by viewModel.submitSuccess.collectAsState()

    var currentIndex by remember { mutableStateOf(0) }

    LaunchedEffect(appLanguage) {
        viewModel.loadQuestions()
    }

    LaunchedEffect(submitSuccess) {
        if (submitSuccess) {
            authViewModel.updateQuestionnaireCompleted(true)
            navController.navigate("main") {
                popUpTo("questionnaire") { inclusive = true }
            }
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0B0B12))
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            // Progress Bar
            val total = 66
            val progress = answers.size
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(
                        text = if (appLanguage == "zh") "第 ${currentIndex + 1} 题 / 共 $total 题" else "Question ${currentIndex + 1} / $total",
                        fontSize = 14.sp,
                        color = Color.Gray
                    )
                    Text(text = "$progress / $total", fontSize = 14.sp, color = Color.White)
                }
                LinearProgressIndicator(
                    progress = (currentIndex + 1).toFloat() / total,
                    modifier = Modifier.fillMaxWidth().height(4.dp),
                    color = Color.Blue,
                    trackColor = Color.Gray.copy(alpha = 0.3f)
                )
            }

            if (isLoading) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = Color.White)
                }
            } else if (loadErrorMessage != null) {
                Column(
                    modifier = Modifier.fillMaxSize().padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Text(
                        text = if (appLanguage == "zh") "加载题目失败" else "Failed to load questions",
                        fontSize = 18.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White
                    )
                    Text(text = loadErrorMessage ?: "", fontSize = 14.sp, color = Color.Gray, modifier = Modifier.padding(vertical = 8.dp))
                    Button(onClick = { viewModel.loadQuestions() }, colors = ButtonDefaults.buttonColors(containerColor = Color.White)) {
                        Text(text = if (appLanguage == "zh") "重试" else "Retry", color = Color.Black)
                    }
                }
            } else if (questions.isNotEmpty()) {
                val currentQuestion = questions.getOrNull(currentIndex)
                if (currentQuestion != null) {
                    Column(modifier = Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp)) {
                        QuestionCard(
                            question = currentQuestion,
                            selectedAnswer = answers[currentQuestion.id],
                            onAnswerSelected = { answer ->
                                viewModel.setAnswer(currentQuestion.id, answer)
                                if (currentIndex < questions.size - 1) {
                                    currentIndex++
                                } else if (answers.size >= 65) {
                                    viewModel.submitAnswers()
                                }
                                Unit
                            },
                            appLanguage = appLanguage
                        )
                    }
                    
                    Row(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
                        Button(
                            onClick = { if (currentIndex > 0) currentIndex-- },
                            enabled = currentIndex > 0,
                            modifier = Modifier.weight(1f).height(50.dp),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = if (currentIndex > 0) Color.White else Color.Gray.copy(alpha = 0.3f)
                            ),
                            shape = RoundedCornerShape(25.dp)
                        ) {
                            Text(text = if (appLanguage == "zh") "上一题" else "Previous", color = Color.Black)
                        }
                    }
                }
            }
        }

        if (isSubmitting) {
            Box(modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.5f)), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = Color.White)
            }
        }
    }

    if (submitErrorMessage != null) {
        AlertDialog(
            onDismissRequest = { viewModel.clearSubmitError() },
            title = { Text(if (appLanguage == "zh") "提交失败" else "Submit Failed") },
            text = { Text(submitErrorMessage ?: "") },
            confirmButton = {
                TextButton(onClick = { viewModel.clearSubmitError() }) {
                    Text(if (appLanguage == "zh") "确定" else "OK")
                }
            }
        )
    }

    if (loadErrorMessage != null) {
        AlertDialog(
            onDismissRequest = { viewModel.clearLoadError() },
            title = { Text(if (appLanguage == "zh") "加载失败" else "Load Failed") },
            text = { Text(loadErrorMessage ?: "") },
            confirmButton = {
                TextButton(onClick = { viewModel.clearLoadError(); viewModel.loadQuestions() }) {
                    Text(if (appLanguage == "zh") "重试" else "Retry")
                }
            }
        )
    }
}

@Composable
fun QuestionCard(
    question: Question,
    selectedAnswer: Int?,
    onAnswerSelected: (Int) -> Unit,
    appLanguage: String
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color.Gray.copy(alpha = 0.1f), RoundedCornerShape(16.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(text = question.text, fontSize = 17.sp, fontWeight = FontWeight.Medium, color = Color.White)
        
        if (question.isSensitive) {
            Text(text = if (appLanguage == "zh") "敏感问题" else "Sensitive", fontSize = 14.sp, color = Color(0xFFFB923C))
        }

        if (question.isLikert) {
            LikertScale(selectedAnswer, onAnswerSelected, appLanguage)
        } else {
            Choice5Scale(selectedAnswer, onAnswerSelected, appLanguage)
        }
    }
}

@Composable
fun LikertScale(selectedAnswer: Int?, onAnswerSelected: (Int) -> Unit, appLanguage: String) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        (1..7).forEach { option ->
            AnswerButton(
                label = getLikertLabel(option, appLanguage),
                isSelected = selectedAnswer == option,
                onClick = { onAnswerSelected(option) }
            )
        }
    }
}

@Composable
fun Choice5Scale(selectedAnswer: Int?, onAnswerSelected: (Int) -> Unit, appLanguage: String) {
    val labels = if (appLanguage == "zh") {
        listOf("坚决不要", "可能不要", "不确定", "可能要", "一定要")
    } else {
        listOf("Definitely no", "Probably no", "Not sure", "Probably yes", "Definitely yes")
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        labels.forEachIndexed { index, label ->
            val option = index + 1
            AnswerButton(
                label = label,
                isSelected = selectedAnswer == option,
                onClick = { onAnswerSelected(option) }
            )
        }
    }
}

@Composable
fun AnswerButton(label: String, isSelected: Boolean, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        colors = ButtonDefaults.buttonColors(
            containerColor = if (isSelected) Color.White else Color.Gray.copy(alpha = 0.2f)
        ),
        shape = RoundedCornerShape(10.dp)
    ) {
        Text(
            text = label,
            modifier = Modifier.fillMaxWidth(),
            color = if (isSelected) Color.Black else Color.White,
            fontSize = 15.sp
        )
    }
}

fun getLikertLabel(option: Int, appLanguage: String): String {
    return when (option) {
        1 -> if (appLanguage == "zh") "强烈反对" else "Strongly disagree"
        2 -> if (appLanguage == "zh") "反对" else "Disagree"
        3 -> if (appLanguage == "zh") "有点反对" else "Slightly disagree"
        4 -> if (appLanguage == "zh") "中立" else "Neutral"
        5 -> if (appLanguage == "zh") "有点同意" else "Slightly agree"
        6 -> if (appLanguage == "zh") "同意" else "Agree"
        7 -> if (appLanguage == "zh") "强烈同意" else "Strongly agree"
        else -> ""
    }
}
