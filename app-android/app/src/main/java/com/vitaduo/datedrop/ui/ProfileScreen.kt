package com.vitaduo.datedrop.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardType
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavController
import com.vitaduo.datedrop.viewmodel.AuthViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen(navController: NavController, authViewModel: AuthViewModel = viewModel()) {
    val appLanguageState = rememberAppLanguage()
    val appLanguage = appLanguageState.value
    val user by authViewModel.currentUser.collectAsState()
    val profileUpdating by authViewModel.profileUpdating.collectAsState()
    val errorMessage by authViewModel.errorMessage.collectAsState()

    var nickname by remember(user?.id) { mutableStateOf(user?.nickname.orEmpty()) }
    var ageText by remember(user?.id) { mutableStateOf(user?.age?.toString().orEmpty()) }
    var gender by remember(user?.id) { mutableStateOf(user?.gender ?: "other") }
    var schoolCareer by remember(user?.id) { mutableStateOf(user?.schoolCareer.orEmpty()) }
    var city by remember(user?.id) { mutableStateOf(user?.city.orEmpty()) }
    var contact by remember(user?.id) { mutableStateOf(user?.contact.orEmpty()) }
    val ageValue = ageText.toIntOrNull()
    val isFormValid = nickname.isNotBlank() && (ageValue ?: 0) in 1..120 && city.isNotBlank()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (appLanguage == "zh") "编辑资料" else "Edit Profile") },
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
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            InputField(
                label = if (appLanguage == "zh") "昵称" else "Nickname",
                placeholder = "",
                value = nickname,
                onValueChange = { nickname = it }
            )
            InputField(
                label = if (appLanguage == "zh") "年龄" else "Age",
                placeholder = "",
                value = ageText,
                onValueChange = { ageText = it },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
            )
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(text = if (appLanguage == "zh") "性别" else "Gender", fontSize = 14.sp, color = Color.Gray)
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    GenderOption(
                        label = if (appLanguage == "zh") "男" else "Male",
                        selected = gender == "male",
                        onClick = { gender = "male" }
                    )
                    GenderOption(
                        label = if (appLanguage == "zh") "女" else "Female",
                        selected = gender == "female",
                        onClick = { gender = "female" }
                    )
                    GenderOption(
                        label = if (appLanguage == "zh") "其他" else "Other",
                        selected = gender == "other",
                        onClick = { gender = "other" }
                    )
                }
            }
            InputField(
                label = if (appLanguage == "zh") "学校/职业" else "School/Job",
                placeholder = "",
                value = schoolCareer,
                onValueChange = { schoolCareer = it }
            )
            InputField(
                label = if (appLanguage == "zh") "城市" else "City",
                placeholder = "",
                value = city,
                onValueChange = { city = it }
            )
            InputField(
                label = if (appLanguage == "zh") "联系方式" else "Contact",
                placeholder = "",
                value = contact,
                onValueChange = { contact = it }
            )
            errorMessage?.let {
                Text(text = it, color = Color.Red, fontSize = 12.sp)
            }
            Button(
                onClick = {
                    val age = ageValue ?: return@Button
                    authViewModel.updateProfile(
                        nickname = nickname.trim(),
                        age = age,
                        gender = gender,
                        schoolCareer = schoolCareer.trim().ifBlank { null },
                        city = city.trim(),
                        contact = contact.trim()
                    )
                },
                modifier = Modifier.fillMaxWidth().height(52.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color.White,
                    disabledContainerColor = Color.White.copy(alpha = 0.5f)
                ),
                shape = RoundedCornerShape(26.dp),
                enabled = isFormValid && !profileUpdating
            ) {
                if (profileUpdating) {
                    CircularProgressIndicator(color = Color.Black, modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                } else {
                    Text(if (appLanguage == "zh") "保存" else "Save", color = Color.Black, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@Composable
fun GenderOption(label: String, selected: Boolean, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        color = if (selected) Color.White else Color.White.copy(alpha = 0.12f),
        shape = RoundedCornerShape(14.dp)
    ) {
        Text(
            text = label,
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
            color = if (selected) Color.Black else Color.White,
            fontSize = 14.sp
        )
    }
}
