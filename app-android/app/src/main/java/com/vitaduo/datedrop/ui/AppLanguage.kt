package com.vitaduo.datedrop.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import com.vitaduo.datedrop.network.NetworkManager

@Composable
fun rememberAppLanguage(): MutableState<String> {
    val initial = remember { NetworkManager.getAppLanguage() }
    val state = remember { mutableStateOf(initial) }
    LaunchedEffect(state.value) {
        NetworkManager.setAppLanguage(state.value)
    }
    return state
}
