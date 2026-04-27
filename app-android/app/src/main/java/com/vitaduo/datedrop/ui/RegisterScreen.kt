package com.vitaduo.datedrop.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavController
import com.vitaduo.datedrop.viewmodel.AuthViewModel

@Composable
fun RegisterScreen(navController: NavController, viewModel: AuthViewModel = viewModel()) {
    val appLanguageState = rememberAppLanguage()
    val appLanguage = appLanguageState.value
    
    var nickname by remember { mutableStateOf("") }
    var age by remember { mutableStateOf("") }
    var genderIndex by remember { mutableStateOf(0) }
    var schoolCareer by remember { mutableStateOf("") }
    var city by remember { mutableStateOf("") }
    var contact by remember { mutableStateOf("") }
    
    val genderValues = listOf("male", "female", "other")
    val genders = if (appLanguage == "zh") listOf("男", "女", "其他") else listOf("Male", "Female", "Other")
    
    val isAuthenticated by viewModel.isAuthenticated.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()
    
    val isFormValid = nickname.isNotBlank() &&
                     age.isNotBlank() &&
                     (age.toIntOrNull() ?: 0) >= 18

    LaunchedEffect(isAuthenticated) {
        if (isAuthenticated) {
            navController.navigate("questionnaire") {
                popUpTo("register") { inclusive = true }
            }
        }
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
                text = if (appLanguage == "zh") "基本信息" else "Basic Info",
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Form Fields
            InputField(
                label = if (appLanguage == "zh") "昵称" else "Nickname",
                placeholder = if (appLanguage == "zh") "输入昵称" else "Enter nickname",
                value = nickname,
                onValueChange = { nickname = it }
            )

            InputField(
                label = if (appLanguage == "zh") "年龄" else "Age",
                placeholder = if (appLanguage == "zh") "输入年龄" else "Enter age",
                value = age,
                onValueChange = { age = it },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
            )

            // Gender Selection
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = if (appLanguage == "zh") "性别" else "Gender",
                    fontSize = 14.sp,
                    color = Color.Gray
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    genders.forEachIndexed { index, label ->
                        val isSelected = genderIndex == index
                        Button(
                            onClick = { genderIndex = index },
                            modifier = Modifier.weight(1f),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = if (isSelected) Color.White else Color.Gray.copy(alpha = 0.2f),
                                contentColor = if (isSelected) Color.Black else Color.White
                            ),
                            shape = RoundedCornerShape(12.dp)
                        ) {
                            Text(label)
                        }
                    }
                }
            }

            InputField(
                label = if (appLanguage == "zh") "学校/职业 (选填)" else "School/Job (Optional)",
                placeholder = if (appLanguage == "zh") "输入学校或职业" else "Enter school or job",
                value = schoolCareer,
                onValueChange = { schoolCareer = it }
            )

            InputField(
                label = if (appLanguage == "zh") "所在城市 (选填)" else "City (Optional)",
                placeholder = if (appLanguage == "zh") "输入城市" else "Enter city",
                value = city,
                onValueChange = { city = it }
            )

            InputField(
                label = if (appLanguage == "zh") "联系方式 (选填)" else "Contact (Optional)",
                placeholder = if (appLanguage == "zh") "输入联系方式" else "Enter contact info",
                value = contact,
                onValueChange = { contact = it },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email)
            )

            Spacer(modifier = Modifier.height(40.dp))

            if (errorMessage != null) {
                Text(
                    text = errorMessage ?: "",
                    color = Color.Red,
                    fontSize = 14.sp,
                    modifier = Modifier.padding(bottom = 16.dp)
                )
            }

            Button(
                onClick = {
                    viewModel.register(
                        nickname,
                        age.toIntOrNull() ?: 0,
                        genderValues[genderIndex],
                        schoolCareer.ifBlank { null },
                        city.ifBlank { null },
                        contact.ifBlank { null }
                    )
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color.White,
                    disabledContainerColor = Color.White.copy(alpha = 0.5f)
                ),
                shape = RoundedCornerShape(28.dp),
                enabled = isFormValid && !isLoading
            ) {
                if (isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        color = Color.Black,
                        strokeWidth = 2.dp
                    )
                } else {
                    Text(
                        text = if (appLanguage == "zh") "下一步" else "Next",
                        fontSize = 18.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.Black
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InputField(
    label: String,
    placeholder: String,
    value: String,
    onValueChange: (String) -> Unit,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(text = label, fontSize = 14.sp, color = Color.Gray)
        TextField(
            value = value,
            onValueChange = onValueChange,
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text(placeholder, color = Color.Gray) },
            keyboardOptions = keyboardOptions,
            colors = TextFieldDefaults.textFieldColors(
                containerColor = Color.Gray.copy(alpha = 0.2f),
                focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
                cursorColor = Color.White,
                focusedTextColor = Color.White,
                unfocusedTextColor = Color.White
            ),
            shape = RoundedCornerShape(12.dp)
        )
    }
}
